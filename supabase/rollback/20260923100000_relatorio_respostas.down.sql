-- Remove o relatório de respostas (as linhas EXPORTAR_RELATORIO em interno.auditoria permanecem: é append-only).
drop function if exists painel.relatorio_respostas(publico.grupo_vaga, publico.nivel_vaga, text);
