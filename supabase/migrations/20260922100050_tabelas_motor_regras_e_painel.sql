-- Fase 2 · Tabelas do motor de regras (pontuação) e do acesso mínimo ao painel interno.
-- Reversão: supabase/rollback/20260922100050_tabelas_motor_regras_e_painel.down.sql
--
-- ATENÇÃO — atalho de hoje: o CLAUDE.md (seção 6, princípio "não negociável" nº 6) exige duas áreas
-- (apps) separadas, com subdomínio próprio e MFA para o painel interno. Por prazo, o painel de hoje
-- roda nas MESMAS rotas/login do portal do candidato, liberado só para quem está em
-- interno.usuarios_internos. Fica registrado como dívida técnica em docs/decisoes-pendentes.md (P5).

------------------------------------------------------------------------------
-- Catálogo de cursos pontuáveis (Anexo I, item 2.1) — referência para o motor
------------------------------------------------------------------------------
create table interno.cursos_pontuaveis (
  grupo        publico.grupo_vaga not null,
  denominacao  text not null,
  primary key (grupo, denominacao)
);
alter table interno.cursos_pontuaveis enable row level security;
revoke all on interno.cursos_pontuaveis from public, anon, authenticated;

------------------------------------------------------------------------------
-- Quem acessa o painel (allowlist mínima; convite de verdade fica para a Fase 3)
------------------------------------------------------------------------------
create table interno.usuarios_internos (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null unique references auth.users (id) on delete restrict,
  nome       text not null,
  email      text not null,
  perfil     text not null default 'comissao',
  ativo      boolean not null default true,
  created_at timestamptz not null default now()
);
alter table interno.usuarios_internos enable row level security;
revoke all on interno.usuarios_internos from public, anon, authenticated;

create or replace function interno.eh_usuario_interno(p_user_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from interno.usuarios_internos u where u.user_id = p_user_id and u.ativo)
$$;

------------------------------------------------------------------------------
-- Resultado do motor de regras, por inscrição (item 6.4 e Anexo I do edital)
-- "rascunho" sempre: nenhum resultado é publicado sem aprovação humana (CLAUDE.md, princípio 2).
------------------------------------------------------------------------------
create table interno.avaliacoes_curriculares (
  id                 uuid primary key default gen_random_uuid(),
  inscricao_id       uuid not null unique references publico.inscricoes (id) on delete cascade,
  habilitado         boolean not null,
  motivos            jsonb not null default '[]'::jsonb,
  pontos_formacao    numeric(5,2) not null default 0,
  pontos_cursos      numeric(5,2) not null default 0,
  pontos_experiencia numeric(5,2) not null default 0,
  total              numeric(5,2) not null default 0,
  detalhamento       jsonb not null default '{}'::jsonb,
  versao_motor       text not null,
  status             text not null default 'rascunho' check (status in ('rascunho', 'aprovada', 'publicada')),
  calculado_em       timestamptz not null default now()
);
alter table interno.avaliacoes_curriculares enable row level security;
revoke all on interno.avaliacoes_curriculares from public, anon, authenticated;
