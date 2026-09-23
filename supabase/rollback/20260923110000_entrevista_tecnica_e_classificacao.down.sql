-- Remove a entrevista técnica e a classificação. ATENÇÃO: apaga as fichas lançadas (o histórico continua em interno.auditoria).
drop function if exists painel.classificacao_final(publico.grupo_vaga, publico.nivel_vaga);
drop function if exists painel.remover_ficha_entrevista(uuid, text);
drop function if exists painel.salvar_ficha_entrevista(uuid, text, jsonb, jsonb);
drop function if exists painel.entrevista_do_candidato(uuid);
drop function if exists interno.eh_convocado(uuid);
drop function if exists interno.recalcular_todas();
drop table if exists interno.fichas_entrevista;
