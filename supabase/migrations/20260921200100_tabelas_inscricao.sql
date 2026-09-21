-- Fase 1 · Tabelas do formulário de inscrição (candidato, inscrição, formação, experiência, documentos).
-- Reversão: supabase/rollback/20260921200100_tabelas_inscricao.down.sql
-- Modelo baseado na seção 7 do CLAUDE.md. Acréscimos necessários ao formulário estão em docs/fase1-backend.md.

------------------------------------------------------------------------------
-- candidatos (1 por conta de login)
------------------------------------------------------------------------------
create table publico.candidatos (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null unique references auth.users (id) on delete restrict,
  nome            text not null check (btrim(nome) ~ '^\S+(\s+\S+)+$' and char_length(nome) <= 200),
  cpf             text not null unique check (publico.cpf_valido(cpf)),
  email           text not null,
  telefone        text not null check (telefone ~ '^\d{10,11}$'),
  data_nascimento date not null check (data_nascimento >= date '1900-01-01'),
  nacionalidade   publico.nacionalidade not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- O e-mail vem SEMPRE da conta autenticada (verificado por código), nunca do formulário.
create or replace function interno.sincronizar_email_candidato() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  select lower(u.email) into new.email from auth.users u where u.id = new.user_id;
  if new.email is null then
    raise exception 'Conta sem e-mail verificado.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

------------------------------------------------------------------------------
-- inscricoes (1 por candidato: item 4.5). Criada automaticamente com o candidato.
------------------------------------------------------------------------------
create table publico.inscricoes (
  id                      uuid primary key default gen_random_uuid(),
  candidato_id            uuid not null unique references publico.candidatos (id) on delete restrict,
  grupo                   publico.grupo_vaga,
  nivel                   publico.nivel_vaga,
  status                  publico.status_inscricao not null default 'rascunho',
  -- graduação (requisito de elegibilidade, itens 5.1.x)
  curso_graduacao         text,
  grau_graduacao          publico.grau_graduacao,
  instituicao_graduacao   text,
  data_colacao            date,
  formato_diploma         publico.formato_diploma,
  codigo_diploma_digital  text,
  diploma_provisorio      boolean not null default false,
  diploma_exterior        boolean not null default false,
  -- vagas reservadas (Cap. X)
  cota_pcd                boolean not null default false,
  data_laudo              date,
  cota_racial             boolean not null default false,
  -- isenção (4.10)
  solicitou_isencao       boolean not null default false,
  justificativa_isencao   text,
  -- declarações finais
  declaracoes_aceitas_em  timestamptz,
  declaracoes_versao      text,
  submetida_em            timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

create or replace function interno.criar_inscricao_do_candidato() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into publico.inscricoes (candidato_id) values (new.id);
  return new;
end;
$$;

------------------------------------------------------------------------------
-- titulos_declarados (pós lato/stricto sensu) e cursos_declarados (cursos e certificações)
------------------------------------------------------------------------------
create table publico.titulos_declarados (
  id             uuid primary key default gen_random_uuid(),
  inscricao_id   uuid not null references publico.inscricoes (id) on delete cascade,
  tipo           publico.tipo_titulo not null,
  denominacao    text not null check (char_length(btrim(denominacao)) between 3 and 300),
  instituicao    text not null check (char_length(btrim(instituicao)) between 2 and 300),
  carga_horaria  integer not null check (carga_horaria > 0),
  data_conclusao date not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table publico.cursos_declarados (
  id                  uuid primary key default gen_random_uuid(),
  inscricao_id        uuid not null references publico.inscricoes (id) on delete cascade,
  tipo                publico.tipo_curso not null,
  denominacao         text not null check (char_length(btrim(denominacao)) between 3 and 300),
  instituicao         text not null check (char_length(btrim(instituicao)) between 2 and 300),
  carga_horaria       integer check (carga_horaria > 0),
  data_conclusao      date not null,
  numero_credencial   text,
  codigo_verificacao  text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  -- 5.2.4: curso exige carga horária expressa; 5.2.3: certificação exige credencial e código de verificação
  constraint ck_curso_ou_certificacao check (
    (tipo = 'curso' and carga_horaria is not null)
    or (tipo = 'certificacao'
        and nullif(btrim(numero_credencial), '') is not null
        and nullif(btrim(codigo_verificacao), '') is not null)
  )
);

------------------------------------------------------------------------------
-- vinculos_declarados (base da regra de não sobreposição, itens 5.4.x)
-- Períodos guardados como o PRIMEIRO DIA do mês (unidade de contagem = mês, inclusive).
-- "concomitante" não é gravado: é derivado da sobreposição entre os vínculos.
------------------------------------------------------------------------------
create table publico.vinculos_declarados (
  id                    uuid primary key default gen_random_uuid(),
  inscricao_id          uuid not null references publico.inscricoes (id) on delete cascade,
  tipo                  publico.tipo_vinculo not null,
  empregador_contratante text not null check (char_length(btrim(empregador_contratante)) between 2 and 300),
  cargo                 text not null check (char_length(btrim(cargo)) between 2 and 200),
  inicio                date not null check (extract(day from inicio) = 1),
  fim                   date,
  ativo                 boolean not null default false,
  descricao             text not null check (char_length(btrim(descricao)) between 10 and 4000),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint ck_fim_ou_ativo check ((ativo and fim is null) or (not ativo and fim is not null)),
  constraint ck_fim_valido check (fim is null or (extract(day from fim) = 1 and fim >= inicio))
);

------------------------------------------------------------------------------
-- documentos (append-only: nunca sobrescreve; "remover" = ativo=false)
------------------------------------------------------------------------------
create table publico.documentos (
  id             uuid primary key default gen_random_uuid(),
  inscricao_id   uuid not null references publico.inscricoes (id) on delete restrict,
  tipo           publico.tipo_documento not null,
  titulo_id      uuid references publico.titulos_declarados (id) on delete set null,
  curso_id       uuid references publico.cursos_declarados (id) on delete set null,
  vinculo_id     uuid references publico.vinculos_declarados (id) on delete set null,
  storage_path   text not null unique,
  nome_original  text not null check (char_length(nome_original) between 1 and 255),
  sha256         text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  mime           text not null check (mime in ('application/pdf', 'image/jpeg', 'image/png')),
  tamanho_bytes  bigint not null check (tamanho_bytes between 1 and 10485760),
  ativo          boolean not null default true,
  enviado_em     timestamptz not null default now(),
  removido_em    timestamptz,
  constraint ck_um_vinculo_no_maximo check (num_nonnulls(titulo_id, curso_id, vinculo_id) <= 1),
  -- caminho no bucket: {inscricao_id}/{tipo}/{uuid}.{ext}
  constraint ck_caminho_da_inscricao check (storage_path like inscricao_id::text || '/%')
);

create or replace function interno.proteger_documento() returns trigger
language plpgsql set search_path = ''
as $$
begin
  if old.ativo and not new.ativo then
    new.removido_em := now();
  elsif not old.ativo and new.ativo then
    raise exception 'Documento removido não pode ser reativado; envie uma nova versão.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

------------------------------------------------------------------------------
-- cursos_aceitos (referência): graduações aceitas por grupo/nível (itens 3.2 a 3.4)
------------------------------------------------------------------------------
create table publico.cursos_aceitos (
  grupo  publico.grupo_vaga  not null,
  nivel  publico.nivel_vaga  not null,
  curso  text                not null,
  primary key (grupo, nivel, curso)
);

------------------------------------------------------------------------------
-- Índices de chave estrangeira
------------------------------------------------------------------------------
create index titulos_declarados_inscricao_idx on publico.titulos_declarados (inscricao_id);
create index cursos_declarados_inscricao_idx  on publico.cursos_declarados (inscricao_id);
create index vinculos_declarados_inscricao_idx on publico.vinculos_declarados (inscricao_id);
create index documentos_inscricao_idx on publico.documentos (inscricao_id);
create index documentos_titulo_idx    on publico.documentos (titulo_id)  where titulo_id  is not null;
create index documentos_curso_idx     on publico.documentos (curso_id)   where curso_id   is not null;
create index documentos_vinculo_idx   on publico.documentos (vinculo_id) where vinculo_id is not null;

------------------------------------------------------------------------------
-- Triggers: updated_at, trava de período, auditoria, encadeamento
------------------------------------------------------------------------------
create trigger candidatos_email_da_conta before insert or update of user_id, email on publico.candidatos
  for each row execute function interno.sincronizar_email_candidato();
create trigger candidatos_cria_inscricao after insert on publico.candidatos
  for each row execute function interno.criar_inscricao_do_candidato();
create trigger documentos_protege before update on publico.documentos
  for each row execute function interno.proteger_documento();

do $$
declare t text;
begin
  foreach t in array array['candidatos', 'inscricoes', 'titulos_declarados', 'cursos_declarados', 'vinculos_declarados', 'documentos']
  loop
    if t <> 'documentos' then
      execute format('create trigger %I before update on publico.%I for each row execute function interno.definir_updated_at()',
                     t || '_updated_at', t);
    end if;
    execute format('create trigger %I before insert or update or delete on publico.%I for each row execute function interno.exigir_periodo_aberto()',
                   t || '_periodo', t);
    execute format('create trigger %I after insert or update or delete on publico.%I for each row execute function interno.registrar_auditoria()',
                   t || '_auditoria', t);
  end loop;
end;
$$;
