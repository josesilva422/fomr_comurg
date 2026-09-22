-- Fase 2 · Acesso de leitura da Comissão a documentos + tabela de extrações por IA.
-- A Comissão precisa ver os documentos para revisar a análise curricular (CLAUDE.md, seção 9: "fila de
-- revisão da Comissão, com documento ao lado dos dados extraídos"). Isso ainda não existia: até aqui só
-- o próprio candidato lia os próprios documentos.
-- Reversão: supabase/rollback/20260922100500_leitura_staff_e_extracoes.down.sql

------------------------------------------------------------------------------
-- Leitura (só SELECT) para quem está em interno.usuarios_internos
------------------------------------------------------------------------------
create policy documentos_staff_le on publico.documentos
  for select to authenticated
  using ((select interno.eh_usuario_interno(auth.uid())));

create policy documentos_staff_le_storage on storage.objects
  for select to authenticated
  using (bucket_id = 'documentos' and (select interno.eh_usuario_interno(auth.uid())));

grant select on publico.titulos_declarados, publico.cursos_declarados, publico.vinculos_declarados to authenticated;
-- (already existem policies de select próprias; adicionamos a leitura da Comissão nelas)
create policy titulos_staff_le on publico.titulos_declarados
  for select to authenticated using ((select interno.eh_usuario_interno(auth.uid())));
create policy cursos_staff_le on publico.cursos_declarados
  for select to authenticated using ((select interno.eh_usuario_interno(auth.uid())));
create policy vinculos_staff_le on publico.vinculos_declarados
  for select to authenticated using ((select interno.eh_usuario_interno(auth.uid())));

------------------------------------------------------------------------------
-- Extrações por IA (CLAUDE.md, seção 7). "O LLM não decide... propõe uma classificação com
-- justificativa e citação, e a Comissão confirma" (seção 9) — status começa sempre 'pendente'.
------------------------------------------------------------------------------
create table interno.extracoes (
  id            uuid primary key default gen_random_uuid(),
  documento_id  uuid not null references publico.documentos (id) on delete cascade,
  modelo        text not null,
  versao_prompt text not null,
  json_extraido jsonb not null,
  evidencias    jsonb not null default '{}'::jsonb,
  confianca     numeric(3,2),
  status        text not null default 'pendente' check (status in ('pendente', 'revisada', 'corrigida')),
  revisado_por  uuid references auth.users (id),
  criado_em     timestamptz not null default now()
);
create index extracoes_documento_idx on interno.extracoes (documento_id);
alter table interno.extracoes enable row level security;
revoke all on interno.extracoes from public, anon, authenticated;

------------------------------------------------------------------------------
-- painel: listar documentos de uma inscrição, e registrar/ler extrações
------------------------------------------------------------------------------
create or replace function painel.documentos_da_inscricao(p_inscricao_id uuid)
returns table (
  id uuid, tipo publico.tipo_documento, nome_original text, storage_path text, mime text,
  tamanho_bytes bigint, enviado_em timestamptz,
  extracao jsonb
)
language plpgsql security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select d.id, d.tipo, d.nome_original, d.storage_path, d.mime, d.tamanho_bytes, d.enviado_em,
      (select to_jsonb(e) - 'documento_id' from interno.extracoes e where e.documento_id = d.id order by e.criado_em desc limit 1)
    from publico.documentos d
    where d.inscricao_id = p_inscricao_id and d.ativo
    order by d.tipo, d.enviado_em;
end;
$$;

create or replace function painel.registrar_extracao(
  p_documento_id uuid, p_modelo text, p_versao_prompt text, p_json_extraido jsonb, p_evidencias jsonb, p_confianca numeric
) returns interno.extracoes
language plpgsql security definer set search_path = ''
as $$
declare resultado interno.extracoes;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  insert into interno.extracoes (documento_id, modelo, versao_prompt, json_extraido, evidencias, confianca)
  values (p_documento_id, p_modelo, p_versao_prompt, p_json_extraido, p_evidencias, p_confianca)
  returning * into resultado;
  return resultado;
end;
$$;

revoke execute on function painel.documentos_da_inscricao(uuid), painel.registrar_extracao(uuid, text, text, jsonb, jsonb, numeric) from public, anon;
grant execute on function painel.documentos_da_inscricao(uuid) to authenticated;
grant execute on function painel.registrar_extracao(uuid, text, text, jsonb, jsonb, numeric) to authenticated;

-- Observação: não há função separada para gerar link do arquivo. Como a Comissão agora tem SELECT em
-- storage.objects (policy acima), o próprio cliente chama supabase.storage.from('documentos')
-- .createSignedUrl(storage_path, ...) normalmente; o RLS de storage já protege o acesso.
