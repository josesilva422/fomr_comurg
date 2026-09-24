-- Login do painel com SENHA + CÓDIGO POR E-MAIL, exigido pelo próprio banco (não só pela tela).
-- Problema anterior: o banco só perguntava "este usuário é da Comissão?". Quem tivesse e-mail e senha podia chamar o
-- Supabase Auth direto, receber uma sessão sem digitar o código e o banco aceitava (docs/decisoes-pendentes.md, D13).
-- Agora:
--   1) a senha do painel é conferida pelo banco (hash bcrypt em interno.usuarios_internos), com bloqueio por tentativas;
--   2) senha correta abre um "desafio" de 10 minutos; só então a tela pede o código por e-mail;
--   3) depois do código, a tela chama painel.concluir_login(): ele só marca a SESSÃO (claim session_id) como liberada
--      se houver um desafio válido — sessão criada sem senha (ex.: código pedido direto ao Auth) nunca é liberada;
--   4) interno.eh_usuario_interno() passa a exigir a sessão liberada (validade de 12 h) — vale para todas as
--      funções do painel e para as políticas RLS/Storage que a usam.
-- A exigência fica atrás do interruptor interno.configuracao 'painel_exige_login_seguro' (começa 'false') para a virada
-- ser feita depois que a tela nova estiver no ar e as senhas definidas. Com 'true' o banco só libera sessão validada.
-- Também guarda CPF de quem acessa o painel (identificação de quem avalia; ver painel.listar_usuarios_painel).
-- Reversão: supabase/rollback/20260924150000_login_painel_senha_e_codigo_no_banco.down.sql

alter table interno.usuarios_internos
  add column senha_hash      text,
  add column cpf             text check (cpf is null or cpf ~ '^[0-9]{11}$'),
  add column tentativas_falhas integer not null default 0,
  add column bloqueado_ate   timestamptz;

create table interno.desafios_login_painel (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references auth.users (id) on delete cascade,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null default now() + interval '10 minutes',
  usado_em  timestamptz
);
create index desafios_login_painel_user_idx on interno.desafios_login_painel (user_id, criado_em desc);
alter table interno.desafios_login_painel enable row level security;
revoke all on interno.desafios_login_painel from public, anon, authenticated;

create table interno.sessoes_painel (
  session_id uuid primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  criada_em  timestamptz not null default now()
);
create index sessoes_painel_user_idx on interno.sessoes_painel (user_id, criada_em desc);
alter table interno.sessoes_painel enable row level security;
revoke all on interno.sessoes_painel from public, anon, authenticated;
create trigger sessoes_painel_auditoria after insert on interno.sessoes_painel
  for each row execute function interno.registrar_auditoria();

insert into interno.configuracao (chave, valor, descricao) values
  ('painel_exige_login_seguro', to_jsonb(false), 'Quando true, o banco só libera o painel a sessões que passaram por senha + código (painel.concluir_login). Ligar depois de a tela nova estar no ar e as senhas definidas.')
on conflict (chave) do nothing;

------------------------------------------------------------------------------
-- Quem é da Comissão: agora exige a sessão liberada (só para o próprio usuário logado, e só com o interruptor ligado)
------------------------------------------------------------------------------
create or replace function interno.eh_usuario_interno(p_user_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from interno.usuarios_internos u where u.user_id = p_user_id and u.ativo)
     and (
       not coalesce((select (c.valor #>> '{}')::boolean from interno.configuracao c where c.chave = 'painel_exige_login_seguro'), false)
       or p_user_id is distinct from auth.uid()
       or exists (
         select 1 from interno.sessoes_painel s
         where s.user_id = p_user_id
           and s.session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid
           and s.criada_em > now() - interval '12 hours'
       )
     )
$$;

------------------------------------------------------------------------------
-- Etapa 1: conferir a senha. Chamada pela tela (anon). Resposta sempre igual em caso de erro (não revela se o e-mail existe).
-- 5 erros seguidos bloqueiam a conta por 15 minutos.
------------------------------------------------------------------------------
create or replace function painel.iniciar_login(p_email text, p_senha text) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  u interno.usuarios_internos;
begin
  select x.* into u from interno.usuarios_internos x
   where lower(x.email) = lower(btrim(coalesce(p_email, ''))) and x.ativo;
  if not found or u.senha_hash is null then
    perform pg_sleep(0.3);  -- iguala o tempo de resposta
    return false;
  end if;
  if u.bloqueado_ate is not null and u.bloqueado_ate > now() then
    return false;
  end if;
  if extensions.crypt(coalesce(p_senha, ''), u.senha_hash) <> u.senha_hash then
    update interno.usuarios_internos x
       set tentativas_falhas = x.tentativas_falhas + 1,
           bloqueado_ate = case when x.tentativas_falhas + 1 >= 5 then now() + interval '15 minutes' end
     where x.id = u.id;
    return false;
  end if;
  update interno.usuarios_internos x set tentativas_falhas = 0, bloqueado_ate = null where x.id = u.id;
  insert into interno.desafios_login_painel (user_id) values (u.user_id);
  return true;
end;
$$;

------------------------------------------------------------------------------
-- Etapa 2: depois de digitar o código (sessão já criada pelo Auth), libera a sessão se a senha foi conferida antes.
------------------------------------------------------------------------------
create or replace function painel.concluir_login() returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_sid uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  v_desafio uuid;
begin
  if v_uid is null or v_sid is null then return false; end if;
  select d.id into v_desafio from interno.desafios_login_painel d
   where d.user_id = v_uid and d.usado_em is null and d.expira_em > now()
   order by d.criado_em desc limit 1
   for update;
  if v_desafio is null or not exists (select 1 from interno.usuarios_internos u where u.user_id = v_uid and u.ativo) then
    return false;
  end if;
  update interno.desafios_login_painel set usado_em = now() where id = v_desafio;
  insert into interno.sessoes_painel (session_id, user_id) values (v_sid, v_uid) on conflict (session_id) do nothing;
  return true;
end;
$$;

------------------------------------------------------------------------------
-- Definir/trocar senha (só administrador do banco; NÃO é exposta à API). Ex.:
--   select interno.definir_senha_painel('pessoa@comurg.com.br', 'senha escolhida');
------------------------------------------------------------------------------
create or replace function interno.definir_senha_painel(p_email text, p_senha text) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if char_length(coalesce(p_senha, '')) < 8
     or p_senha !~ '[A-Z]' or p_senha !~ '[a-z]' or p_senha !~ '[0-9]' or p_senha !~ '[^A-Za-z0-9]' then
    raise exception 'A senha precisa ter no mínimo 8 caracteres, com letra maiúscula, minúscula, número e caractere especial.';
  end if;
  update interno.usuarios_internos
     set senha_hash = extensions.crypt(p_senha, extensions.gen_salt('bf', 10)), tentativas_falhas = 0, bloqueado_ate = null
   where lower(email) = lower(btrim(p_email));
  if not found then raise exception 'Usuário do painel não encontrado.'; end if;
end;
$$;
revoke execute on function interno.definir_senha_painel(text, text) from public, anon, authenticated;

revoke execute on function painel.iniciar_login(text, text), painel.concluir_login() from public;
grant execute on function painel.iniciar_login(text, text) to anon, authenticated;
grant execute on function painel.concluir_login() to authenticated;
