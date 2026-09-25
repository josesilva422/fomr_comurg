-- Convite para a entrevista técnica (itens 6.5.1 e 6.5.7; Anexo IV: convocação até 31/10, entrevistas de 03/11 a 12/11),
-- a pedido do responsável em 25/09/2026. No painel, a Comissão abre o convite de um candidato CONVOCADO (habilitado,
-- AC >= 35 e dentro de 3 por vaga) e informa título, data, horário, link da reunião e orientações adicionais (opcional);
-- o app envia um e-mail padronizado ao candidato. O convite também fica visível no portal do candidato, então ele recebe
-- a informação mesmo que o e-mail falhe.
--
--   * interno.convites_entrevista: histórico de convites (um novo convite substitui o anterior; nada é apagado; auditado);
--   * painel.registrar_convite_entrevista(...): valida e grava; devolve os dados para montar o e-mail;
--   * painel.marcar_convite_enviado(id, enviado, erro): registra o resultado do envio do e-mail;
--   * painel.convites_entrevista_do_candidato(inscricao): histórico, no painel; painel.convites_entrevista_resumo(): lista;
--   * publico.meu_convite_entrevista(): último convite do próprio candidato.
-- Reversão: supabase/rollback/20260925170000_convite_entrevista.down.sql

create table interno.convites_entrevista (
  id            uuid primary key default gen_random_uuid(),
  inscricao_id  uuid not null references publico.inscricoes (id),
  titulo        text not null check (char_length(btrim(titulo)) between 3 and 150),
  data          date not null,
  horario       time not null,
  link          text not null check (link ~* '^https://[^\s]+$' and char_length(link) <= 500),
  orientacoes   text check (orientacoes is null or char_length(orientacoes) <= 2000),
  email_para    text not null,
  enviado_por   uuid not null,
  criado_em     timestamptz not null default clock_timestamp(),
  email_enviado boolean,
  email_erro    text,
  email_em      timestamptz
);
create index convites_entrevista_inscricao_idx on interno.convites_entrevista (inscricao_id, criado_em desc);
alter table interno.convites_entrevista enable row level security;
revoke all on interno.convites_entrevista from public, anon, authenticated;
create trigger convites_entrevista_auditoria after insert or update or delete on interno.convites_entrevista
  for each row execute function interno.registrar_auditoria();

------------------------------------------------------------------------------
-- Painel: registrar o convite (só convocados) e devolver os dados do e-mail.
------------------------------------------------------------------------------
create or replace function painel.registrar_convite_entrevista(
  p_inscricao_id uuid, p_titulo text, p_data date, p_horario time, p_link text, p_orientacoes text
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  c record;
  r interno.convites_entrevista;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  perform interno.recalcular_todas();
  if not interno.eh_convocado(p_inscricao_id) then
    raise exception 'Só candidatos convocados para a entrevista (habilitados, AC ≥ 35 e dentro de 3 por vaga — itens 6.4.4 e 6.5.1) recebem convite.'
      using errcode = 'P0001', hint = 'nao_convocado';
  end if;
  if char_length(btrim(coalesce(p_titulo, ''))) < 3 then
    raise exception 'Informe o título da entrevista.' using errcode = 'P0001', hint = 'titulo_obrigatorio';
  end if;
  if p_data is null or p_horario is null then
    raise exception 'Informe a data e o horário da entrevista.' using errcode = 'P0001', hint = 'data_obrigatoria';
  end if;
  if p_data < (now() at time zone 'America/Sao_Paulo')::date then
    raise exception 'A data da entrevista já passou.' using errcode = 'P0001', hint = 'data_passada';
  end if;
  if btrim(coalesce(p_link, '')) !~* '^https://[^\s]+$' then
    raise exception 'Informe o link da reunião começando com https://' using errcode = 'P0001', hint = 'link_invalido';
  end if;

  select cd.nome, cd.email, i.grupo, i.nivel, i.cota_racial into c
  from publico.inscricoes i join publico.candidatos cd on cd.id = i.candidato_id
  where i.id = p_inscricao_id;
  if c.email is null then
    raise exception 'Candidato sem e-mail cadastrado.' using errcode = 'P0001', hint = 'sem_email';
  end if;

  insert into interno.convites_entrevista (inscricao_id, titulo, data, horario, link, orientacoes, email_para, enviado_por)
  values (p_inscricao_id, btrim(p_titulo), p_data, p_horario, btrim(p_link), nullif(btrim(coalesce(p_orientacoes, '')), ''), c.email, auth.uid())
  returning * into r;

  return jsonb_build_object(
    'id', r.id, 'titulo', r.titulo, 'data', r.data, 'horario', to_char(r.horario, 'HH24:MI'), 'link', r.link,
    'orientacoes', r.orientacoes, 'email', c.email, 'nome', c.nome, 'grupo', c.grupo, 'nivel', c.nivel,
    'cota_racial', c.cota_racial,
    'enviado_por', (select u.nome from interno.usuarios_internos u where u.user_id = auth.uid()));
end;
$$;
revoke execute on function painel.registrar_convite_entrevista(uuid, text, date, time, text, text) from public, anon;
grant execute on function painel.registrar_convite_entrevista(uuid, text, date, time, text, text) to authenticated;

create or replace function painel.marcar_convite_enviado(p_convite_id uuid, p_enviado boolean, p_erro text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  update interno.convites_entrevista
     set email_enviado = p_enviado, email_erro = left(nullif(btrim(coalesce(p_erro, '')), ''), 500), email_em = clock_timestamp()
   where id = p_convite_id and enviado_por = auth.uid();
end;
$$;
revoke execute on function painel.marcar_convite_enviado(uuid, boolean, text) from public, anon;
grant execute on function painel.marcar_convite_enviado(uuid, boolean, text) to authenticated;

create or replace function painel.convites_entrevista_do_candidato(p_inscricao_id uuid)
returns table (
  id uuid, titulo text, data date, horario text, link text, orientacoes text, email_para text,
  criado_em timestamptz, enviado_por text, email_enviado boolean, email_erro text
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select x.id, x.titulo, x.data, to_char(x.horario, 'HH24:MI'), x.link, x.orientacoes, x.email_para, x.criado_em,
           (select u.nome from interno.usuarios_internos u where u.user_id = x.enviado_por), x.email_enviado, x.email_erro
    from interno.convites_entrevista x
    where x.inscricao_id = p_inscricao_id
    order by x.criado_em desc;
end;
$$;
revoke execute on function painel.convites_entrevista_do_candidato(uuid) from public, anon;
grant execute on function painel.convites_entrevista_do_candidato(uuid) to authenticated;

-- Resumo para a lista do painel: último convite de cada candidato.
create or replace function painel.convites_entrevista_resumo()
returns table (inscricao_id uuid, ultimo_em timestamptz, data date, horario text, email_enviado boolean)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select distinct on (x.inscricao_id) x.inscricao_id, x.criado_em, x.data, to_char(x.horario, 'HH24:MI'), x.email_enviado
    from interno.convites_entrevista x
    order by x.inscricao_id, x.criado_em desc;
end;
$$;
revoke execute on function painel.convites_entrevista_resumo() from public, anon;
grant execute on function painel.convites_entrevista_resumo() to authenticated;

------------------------------------------------------------------------------
-- Candidato: último convite (o mais recente substitui os anteriores).
------------------------------------------------------------------------------
create or replace function publico.meu_convite_entrevista()
returns table (titulo text, data date, horario text, link text, orientacoes text, enviado_em timestamptz)
language sql stable security definer set search_path = ''
as $$
  select x.titulo, x.data, to_char(x.horario, 'HH24:MI'), x.link, x.orientacoes, x.criado_em
  from interno.convites_entrevista x
  where x.inscricao_id = (select publico.minha_inscricao_id())
  order by x.criado_em desc
  limit 1
$$;
revoke execute on function publico.meu_convite_entrevista() from public, anon;
grant execute on function publico.meu_convite_entrevista() to authenticated;
