-- Janela de pagamento para quem teve a isenção INDEFERIDA (edital publicado, itens 4.10.2 e 4.9.5 - ressalva):
-- o candidato poderá pagar a taxa até 16/10/2026, às 23h59 (Anexo IV); sem o pagamento nesse prazo, a inscrição é
-- desconsiderada - por DECISÃO MOTIVADA DA COMISSÃO, nunca automática (itens 1.5 e 1.6; decreto, art. 6º, par. único:
-- o indeferimento é comunicado ao interessado).
-- O que muda:
--   * config interno.configuracao 'isencao_pagamento_fim';
--   * o candidato com isenção indeferida (e só ele) pode anexar/remover o COMPROVANTE DE PIX até esse prazo, mesmo depois
--     de a inscrição estar selada e depois do encerramento das inscrições (13/10) - nenhum outro documento;
--   * publico.minha_isencao(): o candidato vê a decisão da Comissão sobre o PRÓPRIO pedido (decisão + motivo + prazo);
--   * decisão 'desconsiderada' (Comissão) depois do prazo, para a inscrição sem pagamento;
--   * painel.listar_isencoes() passa a informar se o comprovante foi enviado e o prazo.
-- Reversão: supabase/rollback/20260924180000_pagamento_apos_isencao_indeferida.down.sql

insert into interno.configuracao (chave, valor, descricao) values
  ('isencao_pagamento_fim', to_jsonb('2026-10-16T23:59:59-03:00'::text), 'Fim do prazo para pagar a taxa após isenção indeferida (edital publicado, item 4.10.2 e Anexo IV: 16/10/2026, 23h59).')
on conflict (chave) do nothing;

alter table interno.decisoes_isencao drop constraint decisoes_isencao_decisao_check;
alter table interno.decisoes_isencao add constraint decisoes_isencao_decisao_check
  check (decisao in ('deferida', 'indeferida', 'desconsiderada'));

------------------------------------------------------------------------------
-- Inscrição do usuário logado SE estiver na janela de pagamento pós-indeferimento (senão, null)
------------------------------------------------------------------------------
create or replace function publico.inscricao_pagamento_pos_isencao_id() returns uuid
language sql stable security definer set search_path = ''
as $$
  select i.id
  from publico.inscricoes i
  join publico.candidatos c on c.id = i.candidato_id
  where c.user_id = (select auth.uid())
    and i.solicitou_isencao
    and i.status = 'aguardando_isencao'
    and now() <= (select (v.valor #>> '{}')::timestamptz from interno.configuracao v where v.chave = 'isencao_pagamento_fim')
    and (select x.decisao from interno.decisoes_isencao x where x.inscricao_id = i.id order by x.decidido_em desc limit 1) = 'indeferida'
$$;
revoke execute on function publico.inscricao_pagamento_pos_isencao_id() from public, anon;
grant execute on function publico.inscricao_pagamento_pos_isencao_id() to authenticated;

------------------------------------------------------------------------------
-- O candidato vê a decisão sobre o PRÓPRIO pedido (vazio enquanto não houver decisão)
------------------------------------------------------------------------------
create or replace function publico.minha_isencao()
returns table (decisao text, motivo text, decidido_em timestamptz, pode_pagar boolean, prazo_pagamento timestamptz)
language sql stable security definer set search_path = ''
as $$
  select d.decisao, d.motivo, d.decidido_em,
         (select publico.inscricao_pagamento_pos_isencao_id()) is not null,
         (select (v.valor #>> '{}')::timestamptz from interno.configuracao v where v.chave = 'isencao_pagamento_fim')
  from interno.decisoes_isencao d
  where d.inscricao_id = (select publico.minha_inscricao_id())
  order by d.decidido_em desc
  limit 1
$$;
revoke execute on function publico.minha_isencao() from public, anon;
grant execute on function publico.minha_isencao() to authenticated;

------------------------------------------------------------------------------
-- RLS: só o COMPROVANTE DE PIX, só nessa janela (documentos e arquivo no Storage)
------------------------------------------------------------------------------
create policy documentos_insert_pos_isencao on publico.documentos
  for insert to authenticated
  with check (
    tipo = 'comprovante_pix'
    and titulo_id is null and curso_id is null and vinculo_id is null
    and inscricao_id = (select publico.inscricao_pagamento_pos_isencao_id())
  );

create policy documentos_update_pos_isencao on publico.documentos
  for update to authenticated
  using (tipo = 'comprovante_pix' and inscricao_id = (select publico.inscricao_pagamento_pos_isencao_id()))
  with check (tipo = 'comprovante_pix' and inscricao_id = (select publico.inscricao_pagamento_pos_isencao_id()));

create policy documentos_candidato_envia_pos_isencao on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'documentos'
    and (storage.foldername(name))[1] = (select publico.inscricao_pagamento_pos_isencao_id())::text
    and (storage.foldername(name))[2] = 'comprovante_pix'
  );

------------------------------------------------------------------------------
-- Trava de prazo: exceção estreita para o comprovante nessa janela
------------------------------------------------------------------------------
create or replace function interno.exigir_periodo_aberto() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_role text := coalesce(auth.jwt() ->> 'role', '');
begin
  if v_role in ('authenticated', 'anon')
     and not (now() between interno.abertura() and interno.encerramento()) then
    if tg_table_name = 'documentos' and tg_op in ('INSERT', 'UPDATE') then
      if new.tipo = 'comprovante_pix' and new.inscricao_id = publico.inscricao_pagamento_pos_isencao_id() then
        return new;
      end if;
    end if;
    raise exception 'Fora do período de inscrições.'
      using errcode = 'P0001', hint = 'inscricoes_fora_do_periodo';
  end if;
  return coalesce(new, old);
end;
$$;

------------------------------------------------------------------------------
-- Painel: lista com comprovante/prazo; decisão 'desconsiderada' só depois do prazo e só após indeferimento
------------------------------------------------------------------------------
drop function if exists painel.listar_isencoes();
create function painel.listar_isencoes()
returns table (
  inscricao_id uuid, nome text, cpf text, grupo publico.grupo_vaga, nivel publico.nivel_vaga,
  status publico.status_inscricao, submetida_em timestamptz,
  hipotese_isencao publico.hipotese_isencao, nis_isencao text, qtd_documentos integer,
  decisao text, motivo text, decidido_em timestamptz,
  comprovante_enviado boolean, prazo_pagamento timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_prazo timestamptz := (select (v.valor #>> '{}')::timestamptz from interno.configuracao v where v.chave = 'isencao_pagamento_fim');
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select i.id, c.nome, c.cpf, i.grupo, i.nivel, i.status, i.submetida_em, i.hipotese_isencao, i.nis_isencao,
           (select count(*)::integer from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'requerimento_isencao'),
           dd.decisao, dd.motivo, dd.decidido_em,
           exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'comprovante_pix'),
           v_prazo
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

create or replace function painel.decidir_isencao(p_inscricao_id uuid, p_decisao text, p_motivo text)
returns interno.decisoes_isencao
language plpgsql security definer set search_path = ''
as $$
declare
  i publico.inscricoes;
  r interno.decisoes_isencao;
  v_ultima text;
  v_prazo timestamptz := (select (v.valor #>> '{}')::timestamptz from interno.configuracao v where v.chave = 'isencao_pagamento_fim');
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if p_decisao not in ('deferida', 'indeferida', 'desconsiderada') then
    raise exception 'Decisão inválida.' using errcode = 'P0001', hint = 'decisao_invalida';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'Informe o motivo da decisão (mínimo de 10 caracteres).' using errcode = 'P0001', hint = 'motivo_obrigatorio';
  end if;
  select x.* into i from publico.inscricoes x where x.id = p_inscricao_id;
  if not found or not i.solicitou_isencao or i.status = 'rascunho' then
    raise exception 'Esta inscrição não tem pedido de isenção enviado.' using errcode = 'P0001', hint = 'sem_pedido_de_isencao';
  end if;
  if p_decisao = 'desconsiderada' then
    select x.decisao into v_ultima from interno.decisoes_isencao x where x.inscricao_id = p_inscricao_id order by x.decidido_em desc limit 1;
    if v_ultima is distinct from 'indeferida' then
      raise exception 'Só se desconsidera a inscrição depois de isenção indeferida.' using errcode = 'P0001', hint = 'desconsiderar_exige_indeferida';
    end if;
    if now() <= v_prazo then
      raise exception 'O prazo de pagamento (item 4.10.2) ainda não terminou.' using errcode = 'P0001', hint = 'prazo_de_pagamento_aberto';
    end if;
  end if;
  insert into interno.decisoes_isencao (inscricao_id, decisao, motivo, decidido_por)
  values (p_inscricao_id, p_decisao, btrim(p_motivo), auth.uid())
  returning * into r;
  return r;
end;
$$;

revoke execute on function painel.listar_isencoes(), painel.decidir_isencao(uuid, text, text) from public, anon;
grant execute on function painel.listar_isencoes(), painel.decidir_isencao(uuid, text, text) to authenticated;
