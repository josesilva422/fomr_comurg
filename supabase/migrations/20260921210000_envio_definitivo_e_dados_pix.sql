-- Fase 1 · (1) ENVIO DEFINITIVO: depois de "Enviar solicitação" a inscrição fica selada; o candidato só LÊ.
--          (2) Dados do Pix na configuração (a chave pode mudar sem novo deploy).
-- Reversão: supabase/rollback/20260921210000_envio_definitivo_e_dados_pix.down.sql

------------------------------------------------------------------------------
-- (1) Somente "rascunho" é editável. Enviada (submetida / aguardando_isencao) = selada.
--     Toda escrita do candidato depende desta função (inscrição, vínculos, títulos, cursos,
--     documentos, Storage, aceite das declarações e envio), então uma única troca sela tudo.
------------------------------------------------------------------------------
create or replace function publico.minha_inscricao_editavel_id() returns uuid
language sql stable security definer set search_path = ''
as $$
  select i.id
  from publico.inscricoes i
  join publico.candidatos c on c.id = i.candidato_id
  where c.user_id = (select auth.uid())
    and i.status = 'rascunho'
$$;

-- O cadastro (nome, CPF, telefone...) também é selado junto com a inscrição.
drop policy if exists candidatos_update_proprio on publico.candidatos;
create policy candidatos_update_proprio on publico.candidatos
  for update to authenticated
  using (user_id = (select auth.uid()) and (select publico.minha_inscricao_editavel_id()) is not null)
  with check (user_id = (select auth.uid()));

------------------------------------------------------------------------------
-- (2) Pix
--     ATENÇÃO: o edital (minuta v2, item 4.9) cita a chave CNPJ 00.418.160/0001-55.
--     O responsável informou a chave abaixo em 21/09/2026; o edital precisa ser ajustado.
------------------------------------------------------------------------------
insert into interno.configuracao (chave, valor, descricao) values
  ('pix_chave',       to_jsonb('pss2026comurg@comurg.com.br'::text), 'Chave Pix para pagamento da taxa (informada pelo responsável em 21/09/2026).'),
  ('pix_tipo_chave',  to_jsonb('email'::text),                        'Tipo da chave Pix: email | cnpj | cpf | telefone | aleatoria.'),
  ('pix_favorecido',  to_jsonb('COMURG'::text),                       'Nome exibido ao candidato como favorecido (conferir com o nome que aparece no app do banco).'),
  ('taxa_inscricao_centavos', to_jsonb(10000),                        'Taxa de inscrição em centavos (item 4.8 do edital: R$ 100,00).')
on conflict (chave) do update
  set valor = excluded.valor, descricao = excluded.descricao, updated_at = now();

create or replace function publico.dados_pagamento()
returns table (pix_chave text, tipo_chave text, favorecido text, valor_centavos integer)
language sql stable security definer set search_path = ''
as $$
  select
    (select c.valor #>> '{}' from interno.configuracao c where c.chave = 'pix_chave'),
    (select c.valor #>> '{}' from interno.configuracao c where c.chave = 'pix_tipo_chave'),
    (select c.valor #>> '{}' from interno.configuracao c where c.chave = 'pix_favorecido'),
    (select (c.valor #>> '{}')::integer from interno.configuracao c where c.chave = 'taxa_inscricao_centavos')
$$;

revoke execute on function publico.dados_pagamento() from public, anon;
grant execute on function publico.dados_pagamento() to authenticated;
