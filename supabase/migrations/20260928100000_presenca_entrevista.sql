-- Presença na entrevista técnica (edital 6.5.7): a Comissão registra, para o candidato convocado, se a entrevista foi
--   * 'realizada'       -> a situação do candidato passa a "Em avaliação pela banca" (as fichas são lançadas pelos avaliadores);
--   * 'nao_compareceu'  -> candidato ELIMINADO por não comparecer (item 6.5.7). É decisão humana, registrada com autor,
--                          data e observação; nada é automático (itens 1.5 e 1.6).
-- O registro é um histórico (a mais recente vale; corrigir = novo registro, nada é apagado; tudo na auditoria).
-- O candidato vê só a própria situação (publico.minha_presenca_entrevista).
-- Regras: só para candidato CONVOCADO e com convite de entrevista registrado; "não compareceu" não pode ser registrado se já
-- houver ficha de avaliador; e não se lança ficha para quem foi eliminado por ausência.
-- Reversão: supabase/rollback/20260928100000_presenca_entrevista.down.sql

create table interno.presenca_entrevista (
  id           uuid primary key default gen_random_uuid(),
  inscricao_id uuid not null references publico.inscricoes (id),
  situacao     text not null check (situacao in ('realizada', 'nao_compareceu')),
  observacao   text check (observacao is null or char_length(observacao) <= 500),
  registrado_por uuid not null,
  registrado_em  timestamptz not null default clock_timestamp()
);
create index presenca_entrevista_inscricao_idx on interno.presenca_entrevista (inscricao_id, registrado_em desc);
alter table interno.presenca_entrevista enable row level security;
revoke all on interno.presenca_entrevista from public, anon, authenticated;
create trigger presenca_entrevista_auditoria after insert or update or delete on interno.presenca_entrevista
  for each row execute function interno.registrar_auditoria();

-- Situação mais recente de um candidato (null = ainda não registrada)
create or replace function interno.presenca_entrevista_atual(p_inscricao_id uuid) returns text
language sql stable security definer set search_path = ''
as $$
  select p.situacao from interno.presenca_entrevista p where p.inscricao_id = p_inscricao_id order by p.registrado_em desc limit 1
$$;
revoke execute on function interno.presenca_entrevista_atual(uuid) from public, anon, authenticated;

------------------------------------------------------------------------------
-- Registrar (Comissão)
------------------------------------------------------------------------------
create or replace function painel.registrar_presenca_entrevista(p_inscricao_id uuid, p_situacao text, p_observacao text default null)
returns interno.presenca_entrevista
language plpgsql security definer set search_path = ''
as $$
declare r interno.presenca_entrevista;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if p_situacao not in ('realizada', 'nao_compareceu') then
    raise exception 'Situação inválida.' using errcode = 'P0001', hint = 'situacao_invalida';
  end if;
  perform interno.recalcular_todas();
  if not interno.eh_convocado(p_inscricao_id) then
    raise exception 'Só candidatos convocados para a entrevista têm presença registrada.' using errcode = 'P0001', hint = 'nao_convocado';
  end if;
  if not exists (select 1 from interno.convites_entrevista c where c.inscricao_id = p_inscricao_id) then
    raise exception 'Registre o convite da entrevista antes de informar a presença.' using errcode = 'P0001', hint = 'sem_convite';
  end if;
  if p_situacao = 'nao_compareceu'
     and exists (select 1 from interno.fichas_entrevista f where f.inscricao_id = p_inscricao_id) then
    raise exception 'Este candidato já tem ficha de avaliador; não é possível registrar ausência.' using errcode = 'P0001', hint = 'ja_tem_ficha';
  end if;
  insert into interno.presenca_entrevista (inscricao_id, situacao, observacao, registrado_por)
  values (p_inscricao_id, p_situacao, nullif(btrim(coalesce(p_observacao, '')), ''), auth.uid())
  returning * into r;
  return r;
end;
$$;

------------------------------------------------------------------------------
-- Histórico no painel
------------------------------------------------------------------------------
create or replace function painel.presenca_entrevista_do_candidato(p_inscricao_id uuid)
returns table (situacao text, observacao text, registrado_por_nome text, registrado_em timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select p.situacao, p.observacao, coalesce(u.nome, '—'), p.registrado_em
    from interno.presenca_entrevista p
    left join interno.usuarios_internos u on u.user_id = p.registrado_por
    where p.inscricao_id = p_inscricao_id
    order by p.registrado_em desc;
end;
$$;

------------------------------------------------------------------------------
-- Candidato: a própria situação na entrevista
------------------------------------------------------------------------------
create or replace function publico.minha_presenca_entrevista()
returns table (situacao text, registrado_em timestamptz)
language sql stable security definer set search_path = ''
as $$
  select p.situacao, p.registrado_em
  from interno.presenca_entrevista p
  where p.inscricao_id = (select publico.minha_inscricao_id())
  order by p.registrado_em desc
  limit 1
$$;

revoke execute on function painel.registrar_presenca_entrevista(uuid, text, text), painel.presenca_entrevista_do_candidato(uuid),
  publico.minha_presenca_entrevista() from public, anon;
grant execute on function painel.registrar_presenca_entrevista(uuid, text, text), painel.presenca_entrevista_do_candidato(uuid),
  publico.minha_presenca_entrevista() to authenticated;

------------------------------------------------------------------------------
-- Não se lança ficha para quem foi eliminado por ausência (troca de texto simples; erro se o trecho não existir)
------------------------------------------------------------------------------
do $$
declare
  d text;
  ancora constant text := $t$  perform interno.recalcular_todas();
  if not interno.eh_convocado(p_inscricao_id) then$t$;
  novo constant text := $t$  if interno.presenca_entrevista_atual(p_inscricao_id) = 'nao_compareceu' then
    raise exception 'Candidato eliminado por não comparecer à entrevista (item 6.5.7); não recebe ficha.' using errcode = 'P0001', hint = 'eliminado_ausencia';
  end if;
$t$ || ancora;
begin
  d := pg_get_functiondef('painel.salvar_ficha_entrevista(uuid,jsonb,jsonb)'::regprocedure);
  if position(ancora in d) = 0 then raise exception 'salvar_ficha_entrevista: trecho não encontrado'; end if;
  execute replace(d, ancora, novo);
end;
$$;
