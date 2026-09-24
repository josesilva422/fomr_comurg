-- Volta a exceção do prazo, as políticas e as funções (listar_isencoes/decidir_isencao de 20260924140000).
create or replace function interno.exigir_periodo_aberto() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_role text := coalesce(auth.jwt() ->> 'role', '');
begin
  if v_role in ('authenticated', 'anon')
     and not (now() between interno.abertura() and interno.encerramento()) then
    raise exception 'Fora do período de inscrições.'
      using errcode = 'P0001', hint = 'inscricoes_fora_do_periodo';
  end if;
  return coalesce(new, old);
end;
$$;
drop policy if exists documentos_candidato_envia_pos_isencao on storage.objects;
drop policy if exists documentos_update_pos_isencao on publico.documentos;
drop policy if exists documentos_insert_pos_isencao on publico.documentos;
drop function if exists publico.minha_isencao();
drop function if exists publico.inscricao_pagamento_pos_isencao_id();
update interno.decisoes_isencao set decisao = 'indeferida' where decisao = 'desconsiderada';
alter table interno.decisoes_isencao drop constraint decisoes_isencao_decisao_check;
alter table interno.decisoes_isencao add constraint decisoes_isencao_decisao_check check (decisao in ('deferida', 'indeferida'));
delete from interno.configuracao where chave = 'isencao_pagamento_fim';
-- Reaplicar painel.listar_isencoes() e painel.decidir_isencao() de 20260924140000_decisao_de_isencao.sql
