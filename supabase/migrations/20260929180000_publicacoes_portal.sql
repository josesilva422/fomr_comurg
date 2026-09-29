-- Página inicial como site oficial do processo (pedido do responsável em 29/09/2026): documentos oficiais (edital,
-- anexos, retificações, resultados), comunicados, cronograma (Anexo IV) e vagas (item 2.1), visíveis sem login.
-- A Comissão publica pelo painel, sem deploy; tudo auditado.
--
--   * publico.publicacoes: documentos (PDF) e comunicados. Só entram por painel.salvar_publicacao; nada é apagado —
--     "retirar do ar" apenas oculta (publicado = false);
--   * bucket 'publicacoes' (privado): a Comissão envia; qualquer pessoa lê SÓ o arquivo de uma publicação publicada
--     (URL assinada gerada na rota /publicacoes/[id]). Sem UPDATE/DELETE: arquivo novo = publicação nova;
--   * publico.listar_publicacoes(), publico.cronograma_publico(), publico.vagas_publicas(): leitura anônima;
--   * painel.listar_publicacoes(), painel.salvar_publicacao(...), painel.publicar_publicacao(id, publicar);
--   * painel.salvar_cronograma_item(...): a Comissão ajusta datas do cronograma (ex.: retificação), com justificativa;
--     interno.cronograma passa a ser auditado.
-- Reversão: supabase/rollback/20260929180000_publicacoes_portal.down.sql

create table publico.publicacoes (
  id             uuid primary key default gen_random_uuid(),
  categoria      text not null check (categoria in ('edital', 'retificacao', 'anexo', 'resultado', 'comunicado', 'outro')),
  titulo         text not null check (char_length(btrim(titulo)) between 3 and 200),
  texto          text check (texto is null or char_length(texto) <= 5000),
  arquivo_path   text unique,
  arquivo_nome   text,
  arquivo_bytes  bigint,
  publicado      boolean not null default false,
  publicado_em   timestamptz,
  criado_por     uuid not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint ck_publicacao_tem_conteudo check (arquivo_path is not null or char_length(btrim(coalesce(texto, ''))) >= 3)
);
create index publicacoes_publicadas_idx on publico.publicacoes (publicado, publicado_em desc);
alter table publico.publicacoes enable row level security;
revoke all on publico.publicacoes from public, anon, authenticated;
create trigger publicacoes_updated_at before update on publico.publicacoes
  for each row execute function interno.definir_updated_at();
create trigger publicacoes_auditoria after insert or update or delete on publico.publicacoes
  for each row execute function interno.registrar_auditoria();

create trigger cronograma_auditoria after insert or update or delete on interno.cronograma
  for each row execute function interno.registrar_auditoria();

------------------------------------------------------------------------------
-- Storage: bucket privado 'publicacoes' (PDF, até 20 MB).
------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('publicacoes', 'publicacoes', false, 20971520, array['application/pdf'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function publico.arquivo_publicado(p_path text) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from publico.publicacoes p where p.arquivo_path = p_path and p.publicado)
$$;
revoke execute on function publico.arquivo_publicado(text) from public;
grant execute on function publico.arquivo_publicado(text) to anon, authenticated;

create policy publicacoes_comissao_envia on storage.objects
  for insert to authenticated
  with check (bucket_id = 'publicacoes' and (select interno.eh_usuario_interno(auth.uid())));

create policy publicacoes_comissao_le on storage.objects
  for select to authenticated
  using (bucket_id = 'publicacoes' and (select interno.eh_usuario_interno(auth.uid())));

create policy publicacoes_publico_le on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'publicacoes' and publico.arquivo_publicado(name));

------------------------------------------------------------------------------
-- Leitura pública.
------------------------------------------------------------------------------
create or replace function publico.listar_publicacoes()
returns table (id uuid, categoria text, titulo text, texto text, tem_arquivo boolean, arquivo_nome text, arquivo_bytes bigint, publicado_em timestamptz)
language sql stable security definer set search_path = ''
as $$
  select p.id, p.categoria, p.titulo, p.texto, p.arquivo_path is not null, p.arquivo_nome, p.arquivo_bytes, p.publicado_em
  from publico.publicacoes p
  where p.publicado
  order by p.publicado_em desc
$$;
revoke execute on function publico.listar_publicacoes() from public;
grant execute on function publico.listar_publicacoes() to anon, authenticated;

-- Caminho do arquivo de uma publicação publicada (para a rota gerar a URL assinada); null se não publicada.
create or replace function publico.arquivo_da_publicacao(p_id uuid)
returns table (arquivo_path text, arquivo_nome text)
language sql stable security definer set search_path = ''
as $$
  select p.arquivo_path, p.arquivo_nome from publico.publicacoes p where p.id = p_id and p.publicado and p.arquivo_path is not null
$$;
revoke execute on function publico.arquivo_da_publicacao(uuid) from public;
grant execute on function publico.arquivo_da_publicacao(uuid) to anon, authenticated;

create or replace function publico.cronograma_publico()
returns table (ordem integer, evento text, data_inicio date, data_fim date, detalhe text)
language sql stable security definer set search_path = ''
as $$
  select c.ordem, c.evento, c.data_inicio, c.data_fim, c.detalhe from interno.cronograma c order by c.ordem
$$;
revoke execute on function publico.cronograma_publico() from public;
grant execute on function publico.cronograma_publico() to anon, authenticated;

create or replace function publico.vagas_publicas()
returns table (grupo publico.grupo_vaga, nivel publico.nivel_vaga, quantidade integer, remuneracao numeric)
language sql stable security definer set search_path = ''
as $$
  select v.grupo, v.nivel, v.quantidade, v.remuneracao from interno.vagas v order by v.nivel, v.grupo
$$;
revoke execute on function publico.vagas_publicas() from public;
grant execute on function publico.vagas_publicas() to anon, authenticated;

------------------------------------------------------------------------------
-- Painel: publicações.
------------------------------------------------------------------------------
create or replace function painel.listar_publicacoes()
returns table (id uuid, categoria text, titulo text, texto text, arquivo_path text, arquivo_nome text, arquivo_bytes bigint,
               publicado boolean, publicado_em timestamptz, criado_por text, created_at timestamptz, updated_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select p.id, p.categoria, p.titulo, p.texto, p.arquivo_path, p.arquivo_nome, p.arquivo_bytes, p.publicado, p.publicado_em,
           (select u.nome from interno.usuarios_internos u where u.user_id = p.criado_por), p.created_at, p.updated_at
    from publico.publicacoes p
    order by p.created_at desc;
end;
$$;
revoke execute on function painel.listar_publicacoes() from public, anon;
grant execute on function painel.listar_publicacoes() to authenticated;

-- Cria (p_id null) ou edita título/texto/categoria. O arquivo só é definido na criação (arquivo novo = publicação nova).
create or replace function painel.salvar_publicacao(
  p_id uuid, p_categoria text, p_titulo text, p_texto text, p_arquivo_path text, p_arquivo_nome text, p_arquivo_bytes bigint
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_titulo, ''))) < 3 then
    raise exception 'Informe o título.' using errcode = 'P0001', hint = 'titulo_obrigatorio';
  end if;
  if p_id is null then
    if p_arquivo_path is not null and not exists (
      select 1 from storage.objects o where o.bucket_id = 'publicacoes' and o.name = p_arquivo_path) then
      raise exception 'Arquivo não encontrado. Envie o PDF de novo.' using errcode = 'P0001', hint = 'arquivo_ausente';
    end if;
    if p_arquivo_path is null and char_length(btrim(coalesce(p_texto, ''))) < 3 then
      raise exception 'Anexe um PDF ou escreva o texto do comunicado.' using errcode = 'P0001', hint = 'conteudo_obrigatorio';
    end if;
    insert into publico.publicacoes (categoria, titulo, texto, arquivo_path, arquivo_nome, arquivo_bytes, criado_por)
    values (p_categoria, btrim(p_titulo), nullif(btrim(coalesce(p_texto, '')), ''), p_arquivo_path, p_arquivo_nome, p_arquivo_bytes, auth.uid())
    returning id into v_id;
  else
    update publico.publicacoes
       set categoria = p_categoria, titulo = btrim(p_titulo), texto = nullif(btrim(coalesce(p_texto, '')), '')
     where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'Publicação não encontrada.' using errcode = 'P0001', hint = 'nao_encontrada';
    end if;
  end if;
  return v_id;
end;
$$;
revoke execute on function painel.salvar_publicacao(uuid, text, text, text, text, text, bigint) from public, anon;
grant execute on function painel.salvar_publicacao(uuid, text, text, text, text, text, bigint) to authenticated;

-- Publica (data de publicação = agora, só na primeira vez) ou retira do ar.
create or replace function painel.publicar_publicacao(p_id uuid, p_publicar boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  update publico.publicacoes
     set publicado = p_publicar, publicado_em = case when p_publicar then coalesce(publicado_em, now()) else publicado_em end
   where id = p_id;
  if not found then
    raise exception 'Publicação não encontrada.' using errcode = 'P0001', hint = 'nao_encontrada';
  end if;
end;
$$;
revoke execute on function painel.publicar_publicacao(uuid, boolean) from public, anon;
grant execute on function painel.publicar_publicacao(uuid, boolean) to authenticated;

------------------------------------------------------------------------------
-- Painel: ajuste do cronograma (ex.: retificação), com justificativa na auditoria.
------------------------------------------------------------------------------
create or replace function painel.salvar_cronograma_item(
  p_ordem integer, p_evento text, p_data_inicio date, p_data_fim date, p_detalhe text, p_justificativa text
) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_justificativa, ''))) < 5 then
    raise exception 'Informe a justificativa da alteração (ex.: retificação nº 1).' using errcode = 'P0001', hint = 'justificativa_obrigatoria';
  end if;
  if char_length(btrim(coalesce(p_evento, ''))) < 3 then
    raise exception 'Informe o evento.' using errcode = 'P0001', hint = 'evento_obrigatorio';
  end if;
  if p_data_inicio is null and p_data_fim is null then
    raise exception 'Informe ao menos uma data.' using errcode = 'P0001', hint = 'data_obrigatoria';
  end if;
  if p_data_inicio is not null and p_data_fim is not null and p_data_fim < p_data_inicio then
    raise exception 'A data final é anterior à inicial.' using errcode = 'P0001', hint = 'datas_invertidas';
  end if;
  update interno.cronograma
     set evento = btrim(p_evento), data_inicio = p_data_inicio, data_fim = p_data_fim, detalhe = nullif(btrim(coalesce(p_detalhe, '')), '')
   where ordem = p_ordem;
  if not found then
    raise exception 'Item do cronograma não encontrado.' using errcode = 'P0001', hint = 'nao_encontrado';
  end if;
  insert into interno.auditoria (ator_id, ator_role, acao, entidade, entidade_id, dados_depois)
  values (auth.uid(), 'authenticated', 'JUSTIFICATIVA_CRONOGRAMA', 'interno.cronograma', p_ordem::text,
          jsonb_build_object('justificativa', btrim(p_justificativa)));
end;
$$;
revoke execute on function painel.salvar_cronograma_item(integer, text, date, date, text, text) from public, anon;
grant execute on function painel.salvar_cronograma_item(integer, text, date, date, text, text) to authenticated;
