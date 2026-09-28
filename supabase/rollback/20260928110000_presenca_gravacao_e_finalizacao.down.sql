-- Reaplicar salvar_ficha_entrevista e remover_minha_ficha sem a checagem de finalização (20260925130000 + 20260928100000)
-- e as funções de presença de 20260928100000 (sem link da gravação) antes de apagar as colunas/tabelas.
drop function if exists painel.entrevista_finalizacao(uuid);
drop function if exists painel.finalizar_entrevista(uuid);
drop function if exists interno.entrevista_esta_finalizada(uuid);
drop table if exists interno.entrevista_finalizada;
alter table interno.presenca_entrevista drop column if exists link_gravacao;
