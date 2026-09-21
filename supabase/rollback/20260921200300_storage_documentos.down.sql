drop policy if exists documentos_candidato_le on storage.objects;
drop policy if exists documentos_candidato_envia on storage.objects;
-- o bucket só pode ser removido se estiver vazio:
delete from storage.buckets where id = 'documentos';
