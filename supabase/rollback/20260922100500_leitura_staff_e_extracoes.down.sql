drop function if exists painel.registrar_extracao(uuid, text, text, jsonb, jsonb, numeric);
drop function if exists painel.documentos_da_inscricao(uuid);
drop table if exists interno.extracoes;
drop policy if exists vinculos_staff_le on publico.vinculos_declarados;
drop policy if exists cursos_staff_le on publico.cursos_declarados;
drop policy if exists titulos_staff_le on publico.titulos_declarados;
drop policy if exists documentos_staff_le_storage on storage.objects;
drop policy if exists documentos_staff_le on publico.documentos;
