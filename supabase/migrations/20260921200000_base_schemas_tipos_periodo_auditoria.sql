-- Fase 1 · Base: schemas, tipos, período de inscrição (trava no servidor) e auditoria imutável.
-- Reversão: supabase/rollback/20260921200000_base_schemas_tipos_periodo_auditoria.down.sql

------------------------------------------------------------------------------
-- Schemas
--   publico : o que o candidato lê e escreve (exposto na API)
--   interno : configuração, auditoria e (futuramente) análise da Comissão.
--             NÃO é exposto na API e não recebe nenhum GRANT para anon/authenticated.
------------------------------------------------------------------------------
create schema if not exists publico;
create schema if not exists interno;

revoke all on schema interno from public, anon, authenticated;
grant usage on schema publico to anon, authenticated;

------------------------------------------------------------------------------
-- Tipos
------------------------------------------------------------------------------
create type publico.grupo_vaga as enum ('A', 'B', 'C');
create type publico.nivel_vaga as enum ('junior', 'pleno', 'senior');
create type publico.status_inscricao as enum
  ('rascunho', 'submetida', 'aguardando_isencao', 'homologada', 'indeferida', 'cancelada');
create type publico.nacionalidade as enum ('brasileiro_nato', 'brasileiro_naturalizado', 'portugues');
create type publico.grau_graduacao as enum ('bacharelado', 'licenciatura', 'tecnologico');
create type publico.formato_diploma as enum ('fisico', 'digital');
create type publico.tipo_titulo as enum ('especializacao', 'mestrado', 'doutorado');
create type publico.tipo_curso as enum ('curso', 'certificacao');
create type publico.tipo_vinculo as enum ('privado', 'publico', 'autonomo');
create type publico.tipo_documento as enum (
  'identidade', 'cpf',
  'diploma_graduacao', 'diploma_pos', 'diploma_mestrado', 'diploma_doutorado',
  'certificado_curso', 'certificacao_profissional',
  'experiencia_ctps', 'experiencia_declaracao', 'experiencia_contrato', 'experiencia_publica', 'experiencia_autonomo',
  'art_rrt_acervo', 'declaracao_lideranca',
  'historico_escolar', 'revalidacao_diploma', 'traducao_juramentada',
  'laudo_pcd', 'autodeclaracao_racial',
  'comprovante_pix', 'requerimento_isencao', 'curriculo_anexo_v'
);

------------------------------------------------------------------------------
-- CPF: validação dos dígitos verificadores (só dígitos, 11 posições)
------------------------------------------------------------------------------
create or replace function publico.cpf_valido(p_cpf text)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = ''
as $$
declare
  d int[];
  s int;
  r int;
begin
  if p_cpf is null or p_cpf !~ '^\d{11}$' or p_cpf ~ '^(\d)\1{10}$' then
    return false;
  end if;
  for k in 1..11 loop
    d[k] := substr(p_cpf, k, 1)::int;
  end loop;
  s := 0;
  for k in 1..9 loop s := s + d[k] * (11 - k); end loop;
  r := (s * 10) % 11; if r = 10 then r := 0; end if;
  if r <> d[10] then return false; end if;
  s := 0;
  for k in 1..10 loop s := s + d[k] * (12 - k); end loop;
  r := (s * 10) % 11; if r = 10 then r := 0; end if;
  return r = d[11];
end;
$$;

------------------------------------------------------------------------------
-- Configuração (chave/valor) e período de inscrição
-- CONFIRMAR com a Comissão o horário exato de abertura e encerramento.
------------------------------------------------------------------------------
create table interno.configuracao (
  chave      text primary key,
  valor      jsonb not null,
  descricao  text,
  updated_at timestamptz not null default now()
);
alter table interno.configuracao enable row level security;  -- sem policies: invisível pela API
revoke all on interno.configuracao from public, anon, authenticated;

insert into interno.configuracao (chave, valor, descricao) values
  ('inscricoes_abertura',    to_jsonb('2026-09-24T00:00:00-03:00'::text), 'Início do período de inscrições (Anexo IV do edital). Horário a confirmar.'),
  ('inscricoes_encerramento', to_jsonb('2026-10-07T23:59:59-03:00'::text), 'Encerramento das inscrições (Anexo IV do edital). Horário a confirmar.');

create or replace function interno.abertura() returns timestamptz
language sql stable security definer set search_path = ''
as $$ select (valor #>> '{}')::timestamptz from interno.configuracao where chave = 'inscricoes_abertura' $$;

create or replace function interno.encerramento() returns timestamptz
language sql stable security definer set search_path = ''
as $$ select (valor #>> '{}')::timestamptz from interno.configuracao where chave = 'inscricoes_encerramento' $$;

revoke execute on function interno.abertura(), interno.encerramento() from public, anon, authenticated;

-- Consulta pública do período (usada pela página inicial e pelas políticas)
create or replace function publico.periodo_inscricoes()
returns table (abertura timestamptz, encerramento timestamptz, agora timestamptz, aberto boolean)
language sql stable security definer set search_path = ''
as $$
  select a, e, now(), now() between a and e
  from (select interno.abertura() as a, interno.encerramento() as e) t
$$;

create or replace function publico.inscricoes_abertas() returns boolean
language sql stable security definer set search_path = ''
as $$ select now() between interno.abertura() and interno.encerramento() $$;

revoke execute on function publico.periodo_inscricoes(), publico.inscricoes_abertas() from public;
grant execute on function publico.periodo_inscricoes(), publico.inscricoes_abertas() to anon, authenticated;

------------------------------------------------------------------------------
-- Triggers utilitários
------------------------------------------------------------------------------
create or replace function interno.definir_updated_at() returns trigger
language plpgsql set search_path = ''
as $$ begin new.updated_at := now(); return new; end; $$;

-- Trava de prazo NO SERVIDOR (itens 5.5.3 e 9.4): contas de candidato (authenticated/anon)
-- não incluem, alteram nem removem nada fora do período. Serviços internos
-- (service_role, migrações, funções administrativas futuras) não são bloqueados aqui.
create or replace function interno.exigir_periodo_aberto() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_role text := coalesce(auth.jwt() ->> 'role', '');
begin
  if v_role in ('authenticated', 'anon')
     and not (now() between interno.abertura() and interno.encerramento()) then
    raise exception 'Fora do período de inscrições.'
      using errcode = 'P0001', hint = 'inscricoes_fora_do_periodo';
  end if;
  return coalesce(new, old);
end;
$$;

------------------------------------------------------------------------------
-- Auditoria append-only (item 13: toda ação relevante fica registrada)
------------------------------------------------------------------------------
create table interno.auditoria (
  id           bigint generated always as identity primary key,
  ocorreu_em   timestamptz not null default now(),
  ator_id      uuid,
  ator_role    text,
  acao         text not null,
  entidade     text not null,
  entidade_id  text,
  dados_antes  jsonb,
  dados_depois jsonb,
  ip           inet
);
create index auditoria_entidade_idx on interno.auditoria (entidade, entidade_id);
create index auditoria_ator_idx on interno.auditoria (ator_id, ocorreu_em);
alter table interno.auditoria enable row level security;
revoke all on interno.auditoria from public, anon, authenticated;

create or replace function interno.auditoria_imutavel() returns trigger
language plpgsql set search_path = ''
as $$ begin raise exception 'interno.auditoria é append-only.' using errcode = 'P0001'; end; $$;

create trigger auditoria_sem_update_delete
  before update or delete on interno.auditoria
  for each row execute function interno.auditoria_imutavel();
create trigger auditoria_sem_truncate
  before truncate on interno.auditoria
  for each statement execute function interno.auditoria_imutavel();

create or replace function interno.registrar_auditoria() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_hdr jsonb;
  v_ip  inet;
begin
  begin v_hdr := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then v_hdr := null; end;
  begin v_ip := split_part(coalesce(v_hdr ->> 'x-forwarded-for', ''), ',', 1)::inet;
  exception when others then v_ip := null; end;

  insert into interno.auditoria (ator_id, ator_role, acao, entidade, entidade_id, dados_antes, dados_depois, ip)
  values (
    auth.uid(),
    auth.jwt() ->> 'role',
    tg_op,
    tg_table_schema || '.' || tg_table_name,
    coalesce(to_jsonb(new) ->> 'id', to_jsonb(old) ->> 'id'),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end,
    v_ip
  );
  return coalesce(new, old);
end;
$$;
