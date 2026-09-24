-- Cadastro de usuários do painel POR CONVITE, dentro do sistema (auditável), sem mexer no Supabase.
-- Fluxo: usuário autorizado convida um e-mail -> link de uso único válido por 12 h -> a pessoa digita o e-mail, recebe o
-- código, digita o código e preenche nome, CPF e a própria senha -> fica cadastrada e com a sessão liberada.
-- Guardamos só o HASH do token. Quem convidou, quando, para qual e-mail e o aceite ficam na auditoria (append-only).
-- Reversão: supabase/rollback/20260924170000_convite_usuarios_painel.down.sql

alter table interno.usuarios_internos
  add column pode_convidar boolean not null default false,
  add column convidado_por uuid references auth.users (id);
create unique index usuarios_internos_cpf_unico on interno.usuarios_internos (cpf) where cpf is not null;
update interno.usuarios_internos set pode_convidar = true where lower(email) = 'josegabrielpo422@gmail.com';

create table interno.convites_painel (
  id         uuid primary key default gen_random_uuid(),
  email      text not null check (email = lower(btrim(email)) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  token_hash text not null unique,
  criado_por uuid not null references auth.users (id),
  criado_em  timestamptz not null default now(),
  expira_em  timestamptz not null default now() + interval '12 hours',
  usado_em   timestamptz,
  usado_por  uuid references auth.users (id),
  cancelado_em timestamptz
);
create index convites_painel_email_idx on interno.convites_painel (email, criado_em desc);
alter table interno.convites_painel enable row level security;
revoke all on interno.convites_painel from public, anon, authenticated;
create trigger convites_painel_auditoria after insert or update or delete on interno.convites_painel
  for each row execute function interno.registrar_auditoria();

------------------------------------------------------------------------------
-- Regra de senha num lugar só (mín. 8; maiúscula, minúscula, número e caractere especial)
------------------------------------------------------------------------------
create or replace function interno.validar_senha_painel(p_senha text) returns void
language plpgsql immutable set search_path = ''
as $$
begin
  if char_length(coalesce(p_senha, '')) < 8
     or p_senha !~ '[A-Z]' or p_senha !~ '[a-z]' or p_senha !~ '[0-9]' or p_senha !~ '[^A-Za-z0-9]' then
    raise exception 'A senha precisa ter no mínimo 8 caracteres, com letra maiúscula, minúscula, número e caractere especial.'
      using errcode = 'P0001', hint = 'senha_fraca';
  end if;
end;
$$;

create or replace function interno.definir_senha_painel(p_email text, p_senha text) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform interno.validar_senha_painel(p_senha);
  update interno.usuarios_internos
     set senha_hash = extensions.crypt(p_senha, extensions.gen_salt('bf', 10)), tentativas_falhas = 0, bloqueado_ate = null
   where lower(email) = lower(btrim(p_email));
  if not found then raise exception 'Usuário do painel não encontrado.'; end if;
end;
$$;
revoke execute on function interno.definir_senha_painel(text, text) from public, anon, authenticated;

------------------------------------------------------------------------------
-- Quem pode convidar (o painel mostra ou esconde o formulário de convite)
------------------------------------------------------------------------------
create or replace function painel.posso_convidar() returns boolean
language sql stable security definer set search_path = ''
as $$
  select interno.eh_usuario_interno(auth.uid())
     and exists (select 1 from interno.usuarios_internos u where u.user_id = auth.uid() and u.ativo and u.pode_convidar)
$$;

------------------------------------------------------------------------------
-- Criar convite: devolve o token UMA vez (para montar o link); no banco fica só o hash. Convite anterior ainda aberto
-- para o mesmo e-mail é cancelado.
------------------------------------------------------------------------------
create or replace function painel.criar_convite(p_email text) returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  if not painel.posso_convidar() then
    raise exception 'Você não tem permissão para convidar usuários.' using errcode = '42501';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Informe um e-mail válido.' using errcode = 'P0001', hint = 'email_invalido';
  end if;
  if exists (select 1 from interno.usuarios_internos u where lower(u.email) = v_email and u.ativo) then
    raise exception 'Este e-mail já tem acesso ao painel.' using errcode = 'P0001', hint = 'ja_e_usuario';
  end if;
  update interno.convites_painel set cancelado_em = now()
   where email = v_email and usado_em is null and cancelado_em is null and expira_em > now();
  insert into interno.convites_painel (email, token_hash, criado_por)
  values (v_email, encode(extensions.digest(v_token, 'sha256'), 'hex'), auth.uid());
  return v_token;
end;
$$;

------------------------------------------------------------------------------
-- Antes de pedir o código: o convite vale e é para este e-mail? (anon; resposta única, sem revelar detalhes)
------------------------------------------------------------------------------
create or replace function painel.conferir_convite(p_token text, p_email text) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from interno.convites_painel c
     where c.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
       and c.email = lower(btrim(coalesce(p_email, '')))
       and c.usado_em is null and c.cancelado_em is null and c.expira_em > now()
  )
$$;

------------------------------------------------------------------------------
-- Aceite: depois do código (sessão criada pelo Auth com o e-mail confirmado). Cria o usuário do painel, define a senha
-- escolhida e libera esta sessão (senha definida agora + código digitado agora).
------------------------------------------------------------------------------
create or replace function painel.aceitar_convite(p_token text, p_nome text, p_cpf text, p_senha text) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_sid uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  v_email text := lower(btrim(coalesce(auth.jwt() ->> 'email', '')));
  v_cpf text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  v_nome text := regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g');
  c interno.convites_painel;
begin
  if v_uid is null or v_sid is null or v_email = '' then
    raise exception 'Sessão inválida.' using errcode = '42501';
  end if;
  select x.* into c from interno.convites_painel x
   where x.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
     and x.email = v_email and x.usado_em is null and x.cancelado_em is null and x.expira_em > now()
   for update;
  if not found then
    raise exception 'Convite inválido, já usado ou expirado.' using errcode = 'P0001', hint = 'convite_invalido';
  end if;
  if v_nome !~ '^\S+( \S+)+$' or char_length(v_nome) < 5 then
    raise exception 'Informe o nome completo.' using errcode = 'P0001', hint = 'nome_invalido';
  end if;
  if not publico.cpf_valido(v_cpf) then
    raise exception 'CPF inválido.' using errcode = 'P0001', hint = 'cpf_invalido';
  end if;
  if exists (select 1 from interno.usuarios_internos u where u.cpf = v_cpf) then
    raise exception 'Este CPF já está cadastrado no painel.' using errcode = 'P0001', hint = 'cpf_duplicado';
  end if;
  perform interno.validar_senha_painel(p_senha);

  insert into interno.usuarios_internos (user_id, nome, email, cpf, perfil, senha_hash, convidado_por)
  values (v_uid, v_nome, v_email, v_cpf, 'comissao', extensions.crypt(p_senha, extensions.gen_salt('bf', 10)), c.criado_por)
  on conflict (user_id) do nothing;
  if not found then
    raise exception 'Este usuário já está cadastrado no painel.' using errcode = 'P0001', hint = 'ja_e_usuario';
  end if;
  update interno.convites_painel set usado_em = now(), usado_por = v_uid where id = c.id;
  insert into interno.sessoes_painel (session_id, user_id) values (v_sid, v_uid) on conflict (session_id) do nothing;
  return true;
end;
$$;

------------------------------------------------------------------------------
-- Convites emitidos (auditoria visível na tela de usuários)
------------------------------------------------------------------------------
create or replace function painel.listar_convites()
returns table (id uuid, email text, convidado_por_nome text, criado_em timestamptz, expira_em timestamptz, situacao text, usado_em timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select c.id, c.email, coalesce(u.nome, '—'), c.criado_em, c.expira_em,
           case when c.usado_em is not null then 'aceito'
                when c.cancelado_em is not null then 'cancelado'
                when c.expira_em <= now() then 'expirado'
                else 'pendente' end,
           c.usado_em
    from interno.convites_painel c
    left join interno.usuarios_internos u on u.user_id = c.criado_por
    order by c.criado_em desc
    limit 200;
end;
$$;

revoke execute on function painel.posso_convidar(), painel.criar_convite(text), painel.conferir_convite(text, text),
  painel.aceitar_convite(text, text, text, text), painel.listar_convites() from public;
grant execute on function painel.posso_convidar(), painel.criar_convite(text), painel.aceitar_convite(text, text, text, text),
  painel.listar_convites() to authenticated;
grant execute on function painel.conferir_convite(text, text) to anon, authenticated;
