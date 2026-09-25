-- Conferência do comprovante do Pix de quem teve a isenção INDEFERIDA (pedido do responsável, 25/09/2026; edital 4.10.2 e
-- 4.9.4). Depois do indeferimento e do envio do comprovante, a Comissão não decide mais a isenção: ela CONFIRMA o
-- pagamento (a inscrição segue o fluxo normal, status 'submetida', igual a quem pagou desde o início) ou RECUSA o
-- comprovante com motivo (o candidato vê o motivo e pode enviar outro até o prazo). Nada é automático (itens 1.5 e 1.6).
--
--   * interno.decisoes_isencao aceita 'pagamento_confirmado' e 'pagamento_recusado';
--   * painel.decidir_pagamento_isencao(inscricao, confirmar, motivo): exige isenção indeferida (ou comprovante antes
--     recusado) e comprovante anexado; ao confirmar, status -> 'submetida';
--   * o candidato volta a poder enviar comprovante depois de uma recusa (dentro do prazo);
--   * "desconsiderar" também vale depois de comprovante recusado; deferir/indeferir deixa de valer depois de pagamento
--     confirmado;
--   * a trava de prazo (interno.exigir_periodo_aberto) deixa passar SÓ a mudança de status feita por essa confirmação,
--     que pode acontecer depois do encerramento das inscrições (13/10).
-- Reversão: supabase/rollback/20260925150000_confirmar_pagamento_pos_isencao.down.sql

alter table interno.decisoes_isencao drop constraint decisoes_isencao_decisao_check;
alter table interno.decisoes_isencao add constraint decisoes_isencao_decisao_check
  check (decisao in ('deferida', 'indeferida', 'desconsiderada', 'pagamento_confirmado', 'pagamento_recusado'));

------------------------------------------------------------------------------
-- Trava de prazo: exceção para a confirmação do pagamento (marcada por uma variável local da transação).
------------------------------------------------------------------------------
do $$
declare d text; ancora text;
begin
  d := pg_get_functiondef('interno.exigir_periodo_aberto()'::regprocedure);
  ancora := '  if v_role in (''authenticated'', ''anon'')';
  if position(ancora in d) = 0 then raise exception 'exigir_periodo_aberto: trecho não encontrado'; end if;
  d := replace(d, ancora,
'  -- confirmação do pagamento pós-isenção pela Comissão (painel.decidir_pagamento_isencao) pode ocorrer após o encerramento
  if tg_table_name = ''inscricoes'' and current_setting(''pss.confirmando_pagamento'', true) = ''on'' then
    return coalesce(new, old);
  end if;
' || ancora);
  execute d;
end;
$$;

------------------------------------------------------------------------------
-- Candidato pode reenviar o comprovante depois de uma recusa (dentro do prazo).
------------------------------------------------------------------------------
do $$
declare d text; ancora text;
begin
  d := pg_get_functiondef('publico.inscricao_pagamento_pos_isencao_id()'::regprocedure);
  ancora := 'limit 1) = ''indeferida''';
  if position(ancora in d) = 0 then raise exception 'inscricao_pagamento_pos_isencao_id: trecho não encontrado'; end if;
  d := replace(d, ancora, 'limit 1) in (''indeferida'', ''pagamento_recusado'')');
  execute d;
end;
$$;

------------------------------------------------------------------------------
-- Decisão sobre a isenção: desconsiderar também após comprovante recusado; nada de deferir/indeferir após pagamento
-- confirmado.
------------------------------------------------------------------------------
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
  select x.decisao into v_ultima from interno.decisoes_isencao x where x.inscricao_id = p_inscricao_id order by x.decidido_em desc limit 1;
  if v_ultima = 'pagamento_confirmado' then
    raise exception 'O pagamento desta inscrição já foi confirmado; ela segue o fluxo normal.' using errcode = 'P0001', hint = 'pagamento_ja_confirmado';
  end if;
  if p_decisao = 'desconsiderada' then
    if v_ultima is null or v_ultima not in ('indeferida', 'pagamento_recusado') then
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

------------------------------------------------------------------------------
-- Conferência do comprovante do Pix após isenção indeferida.
------------------------------------------------------------------------------
create or replace function painel.decidir_pagamento_isencao(p_inscricao_id uuid, p_confirmar boolean, p_motivo text)
returns interno.decisoes_isencao
language plpgsql security definer set search_path = ''
as $$
declare
  i publico.inscricoes;
  r interno.decisoes_isencao;
  v_ultima text;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'Informe o motivo da decisão (mínimo de 10 caracteres).' using errcode = 'P0001', hint = 'motivo_obrigatorio';
  end if;
  select x.* into i from publico.inscricoes x where x.id = p_inscricao_id;
  if not found or not i.solicitou_isencao or i.status <> 'aguardando_isencao' then
    raise exception 'Esta inscrição não está aguardando a conferência do pagamento.' using errcode = 'P0001', hint = 'fora_da_conferencia';
  end if;
  select x.decisao into v_ultima from interno.decisoes_isencao x where x.inscricao_id = p_inscricao_id order by x.decidido_em desc limit 1;
  if v_ultima is null or v_ultima not in ('indeferida', 'pagamento_recusado') then
    raise exception 'A conferência do pagamento só vale depois da isenção indeferida.' using errcode = 'P0001', hint = 'exige_isencao_indeferida';
  end if;
  if not exists (select 1 from publico.documentos d where d.inscricao_id = p_inscricao_id and d.ativo and d.tipo = 'comprovante_pix') then
    raise exception 'O candidato ainda não enviou o comprovante do Pix.' using errcode = 'P0001', hint = 'sem_comprovante';
  end if;

  insert into interno.decisoes_isencao (inscricao_id, decisao, motivo, decidido_por)
  values (p_inscricao_id, case when p_confirmar then 'pagamento_confirmado' else 'pagamento_recusado' end, btrim(p_motivo), auth.uid())
  returning * into r;

  if p_confirmar then
    -- segue o fluxo normal: mesma situação de quem pagou a taxa na inscrição
    perform set_config('pss.confirmando_pagamento', 'on', true);
    update publico.inscricoes set status = 'submetida' where id = p_inscricao_id;
    perform set_config('pss.confirmando_pagamento', 'off', true);
  end if;
  return r;
end;
$$;
revoke execute on function painel.decidir_pagamento_isencao(uuid, boolean, text) from public, anon;
grant execute on function painel.decidir_pagamento_isencao(uuid, boolean, text) to authenticated;
