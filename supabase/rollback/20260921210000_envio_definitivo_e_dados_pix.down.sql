drop function if exists publico.dados_pagamento();
delete from interno.configuracao where chave in ('pix_chave', 'pix_tipo_chave', 'pix_favorecido', 'taxa_inscricao_centavos');
-- volta a permitir edição depois do envio (comportamento anterior)
create or replace function publico.minha_inscricao_editavel_id() returns uuid
language sql stable security definer set search_path = ''
as $$
  select i.id from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id
  where c.user_id = (select auth.uid()) and i.status in ('rascunho', 'submetida', 'aguardando_isencao')
$$;
drop policy if exists candidatos_update_proprio on publico.candidatos;
create policy candidatos_update_proprio on publico.candidatos
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
