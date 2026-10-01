-- Antes de apagar a tabela, reaplicar interno.calcular_avaliacao(uuid) de 20260929170000_minuta_v9_publicacao_05_10.sql
-- (sem a checagem de deliberação; versao_motor volta a 'v8-2026-09-29') e remover a tela/menu do painel
-- (apps/portal-candidato/src/app/painel/(area)/cursos-catalogo e o item em PainelNav.tsx).
drop function if exists painel.decidir_curso_catalogo(uuid, text, text);
drop function if exists painel.listar_cursos_fora_catalogo();
drop table if exists interno.deliberacoes_curso;
