-- Reaplicar painel.salvar_ficha_entrevista(uuid, jsonb, jsonb) de 20260925130000_entrevista_fichas_por_avaliador.sql
-- (remove a checagem de eliminação por ausência) antes de apagar a tabela.
drop function if exists publico.minha_presenca_entrevista();
drop function if exists painel.presenca_entrevista_do_candidato(uuid);
drop function if exists painel.registrar_presenca_entrevista(uuid, text, text);
drop function if exists interno.presenca_entrevista_atual(uuid);
drop table if exists interno.presenca_entrevista;
