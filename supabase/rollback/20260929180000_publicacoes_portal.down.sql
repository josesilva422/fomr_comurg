-- Reverte 20260929180000_publicacoes_portal.sql. Os arquivos do bucket 'publicacoes' ficam no Storage (apagar pelo
-- painel do Supabase, se for o caso); o histórico fica em interno.auditoria.
drop function if exists painel.salvar_cronograma_item(integer, text, date, date, text, text);
drop function if exists painel.publicar_publicacao(uuid, boolean);
drop function if exists painel.salvar_publicacao(uuid, text, text, text, text, text, bigint);
drop function if exists painel.listar_publicacoes();
drop function if exists publico.vagas_publicas();
drop function if exists publico.cronograma_publico();
drop function if exists publico.arquivo_da_publicacao(uuid);
drop function if exists publico.listar_publicacoes();
drop policy if exists publicacoes_publico_le on storage.objects;
drop policy if exists publicacoes_comissao_le on storage.objects;
drop policy if exists publicacoes_comissao_envia on storage.objects;
drop function if exists publico.arquivo_publicado(text);
drop trigger if exists cronograma_auditoria on interno.cronograma;
drop table if exists publico.publicacoes;
