-- Reverte 20260925170000_convite_entrevista.sql (apaga o histórico de convites; o registro fica em interno.auditoria).
drop function if exists publico.meu_convite_entrevista();
drop function if exists painel.convites_entrevista_resumo();
drop function if exists painel.convites_entrevista_do_candidato(uuid);
drop function if exists painel.marcar_convite_enviado(uuid, boolean, text);
drop function if exists painel.registrar_convite_entrevista(uuid, text, date, time, text, text);
drop table if exists interno.convites_entrevista;
