drop function if exists painel.listar_recursos();
drop function if exists painel.decidir_recurso(uuid, boolean, text);
drop function if exists painel.registrar_recurso(uuid, text, date, text);
drop table if exists interno.recursos;
