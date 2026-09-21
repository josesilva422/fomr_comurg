-- Fase 1 · Bucket privado de documentos.
-- Caminho do objeto: {inscricao_id}/{tipo}/{uuid}.{ext}  (a 1ª pasta é a inscrição do dono).
-- Candidato: envia e lê só os próprios arquivos, e só no período. Não altera nem apaga (nova versão = novo arquivo).
-- Limite de 10 MB e tipos PDF/JPG/PNG são valores provisórios (docs/decisoes-pendentes.md).
-- Reversão: supabase/rollback/20260921200300_storage_documentos.down.sql

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('documentos', 'documentos', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy documentos_candidato_envia on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'documentos'
    and (storage.foldername(name))[1] = (select publico.minha_inscricao_editavel_id())::text
    and (select publico.inscricoes_abertas())
  );

create policy documentos_candidato_le on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documentos'
    and (storage.foldername(name))[1] = (select publico.minha_inscricao_id())::text
  );
