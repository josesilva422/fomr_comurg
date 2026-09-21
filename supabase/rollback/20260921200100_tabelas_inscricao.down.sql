-- ATENÇÃO: apaga todos os dados de inscrição. Só em ambiente de desenvolvimento.
drop table if exists publico.cursos_aceitos;
drop table if exists publico.documentos;
drop table if exists publico.vinculos_declarados;
drop table if exists publico.cursos_declarados;
drop table if exists publico.titulos_declarados;
drop table if exists publico.inscricoes;
drop table if exists publico.candidatos;
drop function if exists interno.criar_inscricao_do_candidato();
drop function if exists interno.sincronizar_email_candidato();
drop function if exists interno.proteger_documento();
