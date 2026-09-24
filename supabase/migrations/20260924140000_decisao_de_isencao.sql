-- Decisão da Comissão sobre os pedidos de isenção da taxa (edital 4.10, 4.10.1 e 4.10.2; decreto municipal, art. 4º).
-- A decisão é HUMANA, motivada e registrada (itens 1.5 e 1.6): o sistema só guarda o que a Comissão decidir.
-- Fica numa tabela própria do schema interno (não altera publico.inscricoes, que tem trava de período), com
-- histórico: uma nova decisão (ex.: após recurso) não apaga a anterior; vale a mais recente.
-- Reversão: supabase/rollback/20260924140000_decisao_de_isencao.down.sql

create table interno.decisoes_isencao (
  id           uuid primary key default gen_random_uuid(),
  inscricao_id uuid not null references publico.inscricoes (id),
  decisao      text not null check (decisao in ('deferida', 'indeferida')),
  motivo       text not null check (char_length(btrim(motivo)) >= 10),
  decidido_por uuid not null,
  decidido_em  timestamptz not null default clock_timestamp()
);
create index decisoes_isencao_inscricao_idx on interno.decisoes_isencao (inscricao_id, decidido_em desc);
alter table interno.decisoes_isencao enable row level security;
revoke all on interno.decisoes_isencao from public, anon, authenticated;

create trigger decisoes_isencao_auditoria after insert or update or delete on interno.decisoes_isencao
  for each row execute function interno.registrar_auditoria();

------------------------------------------------------------------------------
-- Lista dos pedidos de isenção (só inscrições enviadas) com a decisão mais recente
------------------------------------------------------------------------------
create or replace function painel.listar_isencoes()
returns table (
  inscricao_id uuid, nome text, cpf text, grupo publico.grupo_vaga, nivel publico.nivel_vaga,
  status publico.status_inscricao, submetida_em timestamptz,
  hipotese_isencao publico.hipotese_isencao, nis_isencao text, qtd_documentos integer,
  decisao text, motivo text, decidido_em timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select i.id, c.nome, c.cpf, i.grupo, i.nivel, i.status, i.submetida_em, i.hipotese_isencao, i.nis_isencao,
           (select count(*)::integer from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'requerimento_isencao'),
           dd.decisao, dd.motivo, dd.decidido_em
    from publico.inscricoes i
    join publico.candidatos c on c.id = i.candidato_id
    left join lateral (
      select x.decisao, x.motivo, x.decidido_em from interno.decisoes_isencao x
      where x.inscricao_id = i.id order by x.decidido_em desc limit 1
    ) dd on true
    where i.solicitou_isencao and i.status <> 'rascunho'
    order by (dd.decisao is null) desc, i.submetida_em;
end;
$$;

------------------------------------------------------------------------------
-- Registrar a decisão (motivo obrigatório, com no mínimo 10 caracteres)
------------------------------------------------------------------------------
create or replace function painel.decidir_isencao(p_inscricao_id uuid, p_decisao text, p_motivo text)
returns interno.decisoes_isencao
language plpgsql security definer set search_path = ''
as $$
declare
  i publico.inscricoes;
  r interno.decisoes_isencao;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if p_decisao not in ('deferida', 'indeferida') then
    raise exception 'Decisão inválida.' using errcode = 'P0001', hint = 'decisao_invalida';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'Informe o motivo da decisão (mínimo de 10 caracteres).' using errcode = 'P0001', hint = 'motivo_obrigatorio';
  end if;
  select x.* into i from publico.inscricoes x where x.id = p_inscricao_id;
  if not found or not i.solicitou_isencao or i.status = 'rascunho' then
    raise exception 'Esta inscrição não tem pedido de isenção enviado.' using errcode = 'P0001', hint = 'sem_pedido_de_isencao';
  end if;
  insert into interno.decisoes_isencao (inscricao_id, decisao, motivo, decidido_por)
  values (p_inscricao_id, p_decisao, btrim(p_motivo), auth.uid())
  returning * into r;
  return r;
end;
$$;

revoke execute on function painel.listar_isencoes(), painel.decidir_isencao(uuid, text, text) from public, anon;
grant execute on function painel.listar_isencoes(), painel.decidir_isencao(uuid, text, text) to authenticated;
