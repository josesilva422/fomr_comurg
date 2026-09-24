-- Remove hipótese/NIS da isenção. Antes, reaplique publico.verificar_inscricao() de 20260924120000 e as funções
-- interno.registro_formulario / painel.dados_declarados_documento das migrações anteriores (elas referenciam as colunas).
delete from interno.configuracao where chave = 'isencao_pedidos_fim';
alter table publico.inscricoes drop column if exists hipotese_isencao, drop column if exists nis_isencao;
drop type if exists publico.hipotese_isencao;
