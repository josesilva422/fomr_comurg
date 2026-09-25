-- Volta ao estado anterior à migração 20260925160000.

drop function if exists publico.meu_formulario();
drop function if exists publico.minha_decisao_inscricao();
drop function if exists painel.decidir_inscricao(uuid, boolean, text);
drop function if exists painel.listar_homologacao();
drop function if exists interno.pode_homologar(uuid);
drop function if exists interno.pagamento_da_inscricao(uuid);

CREATE OR REPLACE FUNCTION interno.exigir_periodo_aberto()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text := coalesce(auth.jwt() ->> 'role', '');
begin
  -- confirmação do pagamento pós-isenção pela Comissão (painel.decidir_pagamento_isencao) pode ocorrer após o encerramento
  if tg_table_name = 'inscricoes' and current_setting('pss.confirmando_pagamento', true) = 'on' then
    return coalesce(new, old);
  end if;
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

drop table interno.decisoes_inscricao;
-- Obs.: inscrições já homologadas/indeferidas continuam com esse status; volte-as a 'submetida' manualmente se precisar.
