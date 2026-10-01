drop function if exists painel.publicacoes_ac();
drop function if exists painel.publicar_resultados_ac_lote(text, publico.grupo_vaga, publico.nivel_vaga, text);
drop function if exists painel.publicar_resultado_ac(uuid, text, text);
drop table if exists publico.resultados_candidato;
