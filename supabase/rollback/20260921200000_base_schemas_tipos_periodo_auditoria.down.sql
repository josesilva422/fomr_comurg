-- ATENÇÃO: só em ambiente de desenvolvimento (a auditoria é imutável por desenho).
drop table if exists interno.auditoria;
drop table if exists interno.configuracao;
drop function if exists interno.registrar_auditoria();
drop function if exists interno.auditoria_imutavel();
drop function if exists interno.exigir_periodo_aberto();
drop function if exists interno.definir_updated_at();
drop function if exists interno.abertura();
drop function if exists interno.encerramento();
drop function if exists publico.periodo_inscricoes();
drop function if exists publico.inscricoes_abertas();
drop function if exists publico.cpf_valido(text);
drop type if exists publico.tipo_documento, publico.tipo_vinculo, publico.tipo_curso, publico.tipo_titulo,
  publico.formato_diploma, publico.grau_graduacao, publico.nacionalidade, publico.status_inscricao,
  publico.nivel_vaga, publico.grupo_vaga;
drop schema if exists interno;
drop schema if exists publico;
