-- Homologação das inscrições (edital, Anexo IV item 10: até 20/10/2026; recurso contra indeferimento, 9.1.b), a pedido do
-- responsável em 25/09/2026. Um membro da Comissão APROVA ou REJEITA cada inscrição enviada. Rejeitar exige explicação
-- (item 1.6); aprovar não. O candidato vê "inscrição aprovada" ou "inscrição rejeitada" com o motivo.
--
--   * interno.decisoes_inscricao: histórico das decisões (auditado);
--   * painel.listar_homologacao(): inscrições que podem ser homologadas (enviadas com Pix, com isenção deferida ou com
--     pagamento confirmado após isenção indeferida), com a forma de pagamento e a última decisão;
--   * painel.decidir_inscricao(inscricao, aprovar, motivo): aprovada -> status 'homologada'; rejeitada -> 'indeferida'.
--     Pode ser refeita (ex.: após recurso), sempre com registro;
--   * publico.minha_decisao_inscricao(): o candidato vê a decisão (motivo só na rejeição);
--   * publico.meu_formulario(): o candidato consulta as próprias respostas (mesmo registro do painel/relatório);
--   * a trava de prazo deixa passar essa mudança de status (a homologação é depois de 13/10).
-- Inscrição rejeitada ('indeferida') sai da análise curricular e da convocação (que só consideram submetida,
-- aguardando_isencao e homologada).
-- Reversão: supabase/rollback/20260925160000_homologacao_inscricoes.down.sql

create table interno.decisoes_inscricao (
  id           uuid primary key default gen_random_uuid(),
  inscricao_id uuid not null references publico.inscricoes (id),
  decisao      text not null check (decisao in ('aprovada', 'rejeitada')),
  motivo       text,
  decidido_por uuid not null,
  decidido_em  timestamptz not null default clock_timestamp(),
  constraint ck_motivo_da_rejeicao check (decisao = 'aprovada' or char_length(btrim(coalesce(motivo, ''))) >= 10)
);
create index decisoes_inscricao_inscricao_idx on interno.decisoes_inscricao (inscricao_id, decidido_em desc);
alter table interno.decisoes_inscricao enable row level security;
revoke all on interno.decisoes_inscricao from public, anon, authenticated;
create trigger decisoes_inscricao_auditoria after insert or update or delete on interno.decisoes_inscricao
  for each row execute function interno.registrar_auditoria();

------------------------------------------------------------------------------
-- Trava de prazo: a mudança de status feita pela decisão da Comissão também passa (após 13/10).
------------------------------------------------------------------------------
do $$
declare d text; ancora text;
begin
  d := pg_get_functiondef('interno.exigir_periodo_aberto()'::regprocedure);
  ancora := 'current_setting(''pss.confirmando_pagamento'', true) = ''on''';
  if position(ancora in d) = 0 then raise exception 'exigir_periodo_aberto: exceção da confirmação de pagamento não encontrada'; end if;
  d := replace(d, ancora,
    '(current_setting(''pss.confirmando_pagamento'', true) = ''on'' or current_setting(''pss.decisao_comissao'', true) = ''on'')');
  execute d;
end;
$$;

------------------------------------------------------------------------------
-- Forma de pagamento e se a inscrição pode ser homologada.
------------------------------------------------------------------------------
create or replace function interno.pagamento_da_inscricao(p_inscricao_id uuid) returns text
language sql stable security definer set search_path = ''
as $$
  select case
    when not i.solicitou_isencao then 'pix'
    when d.decisao = 'deferida' then 'isencao'
    when d.decisao = 'pagamento_confirmado' then 'pix_apos_isencao'
    else null
  end
  from publico.inscricoes i
  left join lateral (
    select x.decisao from interno.decisoes_isencao x where x.inscricao_id = i.id order by x.decidido_em desc limit 1
  ) d on true
  where i.id = p_inscricao_id
$$;
revoke execute on function interno.pagamento_da_inscricao(uuid) from public, anon, authenticated;

create or replace function interno.pode_homologar(p_inscricao_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from publico.inscricoes i
    where i.id = p_inscricao_id
      and (i.status in ('submetida', 'homologada', 'indeferida')
           or (i.status = 'aguardando_isencao' and interno.pagamento_da_inscricao(i.id) = 'isencao'))
  )
$$;
revoke execute on function interno.pode_homologar(uuid) from public, anon, authenticated;

------------------------------------------------------------------------------
-- Painel: lista para homologação.
------------------------------------------------------------------------------
create or replace function painel.listar_homologacao()
returns table (
  inscricao_id uuid, nome text, cpf text, grupo publico.grupo_vaga, nivel publico.nivel_vaga,
  status publico.status_inscricao, submetida_em timestamptz, pagamento text,
  decisao text, motivo text, decidido_em timestamptz, decidido_por text
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select i.id, c.nome, c.cpf, i.grupo, i.nivel, i.status, i.submetida_em, interno.pagamento_da_inscricao(i.id),
           d.decisao, d.motivo, d.decidido_em, (select u.nome from interno.usuarios_internos u where u.user_id = d.decidido_por)
    from publico.inscricoes i
    join publico.candidatos c on c.id = i.candidato_id
    left join lateral (
      select x.decisao, x.motivo, x.decidido_em, x.decidido_por from interno.decisoes_inscricao x
      where x.inscricao_id = i.id order by x.decidido_em desc limit 1
    ) d on true
    where interno.pode_homologar(i.id)
    order by (d.decisao is null) desc, i.submetida_em;
end;
$$;
revoke execute on function painel.listar_homologacao() from public, anon;
grant execute on function painel.listar_homologacao() to authenticated;

------------------------------------------------------------------------------
-- Painel: aprovar ou rejeitar (rejeição com explicação).
------------------------------------------------------------------------------
create or replace function painel.decidir_inscricao(p_inscricao_id uuid, p_aprovar boolean, p_motivo text)
returns interno.decisoes_inscricao
language plpgsql security definer set search_path = ''
as $$
declare
  r interno.decisoes_inscricao;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if not interno.pode_homologar(p_inscricao_id) then
    raise exception 'Esta inscrição ainda não pode ser homologada (não enviada, isenção sem decisão ou pagamento não confirmado).'
      using errcode = 'P0001', hint = 'fora_da_homologacao';
  end if;
  if not p_aprovar and char_length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'Explique o motivo da rejeição (mínimo de 10 caracteres).' using errcode = 'P0001', hint = 'motivo_obrigatorio';
  end if;

  insert into interno.decisoes_inscricao (inscricao_id, decisao, motivo, decidido_por)
  values (p_inscricao_id, case when p_aprovar then 'aprovada' else 'rejeitada' end,
          nullif(btrim(coalesce(p_motivo, '')), ''), auth.uid())
  returning * into r;

  perform set_config('pss.decisao_comissao', 'on', true);
  update publico.inscricoes set status = case when p_aprovar then 'homologada' else 'indeferida' end::publico.status_inscricao
   where id = p_inscricao_id;
  perform set_config('pss.decisao_comissao', 'off', true);
  return r;
end;
$$;
revoke execute on function painel.decidir_inscricao(uuid, boolean, text) from public, anon;
grant execute on function painel.decidir_inscricao(uuid, boolean, text) to authenticated;

------------------------------------------------------------------------------
-- Candidato: decisão sobre a própria inscrição (motivo só na rejeição) e o próprio formulário.
------------------------------------------------------------------------------
create or replace function publico.minha_decisao_inscricao()
returns table (decisao text, motivo text, decidido_em timestamptz)
language sql stable security definer set search_path = ''
as $$
  select d.decisao, case when d.decisao = 'rejeitada' then d.motivo end, d.decidido_em
  from interno.decisoes_inscricao d
  where d.inscricao_id = (select publico.minha_inscricao_id())
  order by d.decidido_em desc
  limit 1
$$;
revoke execute on function publico.minha_decisao_inscricao() from public, anon;
grant execute on function publico.minha_decisao_inscricao() to authenticated;

create or replace function publico.meu_formulario()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select interno.registro_formulario(i.id)
  from publico.inscricoes i
  where i.id = (select publico.minha_inscricao_id())
$$;
revoke execute on function publico.meu_formulario() from public, anon;
grant execute on function publico.meu_formulario() to authenticated;
