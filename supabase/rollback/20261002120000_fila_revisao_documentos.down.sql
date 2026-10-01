drop function if exists painel.listar_fila_revisao(text);
drop function if exists painel.revisar_extracao(uuid, text, text);
alter table interno.extracoes drop column if exists observacao_revisao;
alter table interno.extracoes drop column if exists revisado_em;
