-- Volta ao estado anterior à migração 20260925150000 (definições completas salvas antes da mudança).

drop function if exists painel.decidir_pagamento_isencao(uuid, boolean, text);

CREATE OR REPLACE FUNCTION interno.exigir_periodo_aberto()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$

;

CREATE OR REPLACE FUNCTION publico.inscricao_pagamento_pos_isencao_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select i.id
  from publico.inscricoes i
  join publico.candidatos c on c.id = i.candidato_id
  where c.user_id = (select auth.uid())
    and i.solicitou_isencao
    and i.status = 'aguardando_isencao'
    and now() <= (select (v.valor #>> '{}')::timestamptz from interno.configuracao v where v.chave = 'isencao_pagamento_fim')
    and (select x.decisao from interno.decisoes_isencao x where x.inscricao_id = i.id order by x.decidido_em desc limit 1) = 'indeferida'
$function$

;

CREATE OR REPLACE FUNCTION painel.decidir_isencao(p_inscricao_id uuid, p_decisao text, p_motivo text)
 RETURNS interno.decisoes_isencao
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$

;

-- decisões novas não cabem na restrição antiga: registre-as antes de reverter, se houver
alter table interno.decisoes_isencao drop constraint decisoes_isencao_decisao_check;
alter table interno.decisoes_isencao add constraint decisoes_isencao_decisao_check check (decisao in ('deferida', 'indeferida', 'desconsiderada'));
