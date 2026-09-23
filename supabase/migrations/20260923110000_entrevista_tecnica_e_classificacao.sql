-- Fase 4 (início) · Entrevista técnica (edital 6.5 e Anexo II) e classificação (PF = AC + ET, item 7.2), a pedido do
-- responsável em 23/09/2026. A entrevista acontece FORA do sistema (call, gravação e transcrição externas); aqui a
-- Comissão LANÇA as notas por competência de cada avaliador (transcrição da ficha do Anexo II), e o sistema faz:
--   ET = média aritmética das notas totais dos avaliadores (6.5.5); < 15 pts = abaixo do corte (6.5.7);
--   PF = AC + ET (máx. 100); classificação por Grupo/Nível com os desempates do item 7.2.
-- Nada disso decide sozinho: "abaixo do corte" é SINALIZAÇÃO; a eliminação continua sendo decisão da Comissão.
-- Só candidatos CONVOCADOS (6.4.4 e 6.5.1) podem ter ficha. Cada alteração vai para interno.auditoria.
-- Reversão: supabase/rollback/20260923110000_entrevista_tecnica_e_classificacao.down.sql

create table interno.fichas_entrevista (
  id                 uuid primary key default gen_random_uuid(),
  inscricao_id       uuid not null references publico.inscricoes (id) on delete cascade,
  avaliador_nome     text not null check (char_length(btrim(avaliador_nome)) between 3 and 200),
  -- Anexo II: pesos 10, 10, 5, 5, 5, 5 (total 40); nota inteira dentro do peso
  nota_dominio       smallint not null check (nota_dominio between 0 and 10),
  nota_analise       smallint not null check (nota_analise between 0 and 10),
  nota_planejamento  smallint not null check (nota_planejamento between 0 and 5),
  nota_comunicacao   smallint not null check (nota_comunicacao between 0 and 5),
  nota_caso          smallint not null check (nota_caso between 0 and 5),
  nota_postura       smallint not null check (nota_postura between 0 and 5),
  just_dominio       text not null check (char_length(btrim(just_dominio)) >= 3),
  just_analise       text not null check (char_length(btrim(just_analise)) >= 3),
  just_planejamento  text not null check (char_length(btrim(just_planejamento)) >= 3),
  just_comunicacao   text not null check (char_length(btrim(just_comunicacao)) >= 3),
  just_caso          text not null check (char_length(btrim(just_caso)) >= 3),
  just_postura       text not null check (char_length(btrim(just_postura)) >= 3),
  total              smallint generated always as
                       (nota_dominio + nota_analise + nota_planejamento + nota_comunicacao + nota_caso + nota_postura) stored,
  lancado_por        uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (inscricao_id, avaliador_nome)
);
alter table interno.fichas_entrevista enable row level security;
revoke all on interno.fichas_entrevista from public, anon, authenticated;
create index fichas_entrevista_inscricao_idx on interno.fichas_entrevista (inscricao_id);
create trigger fichas_entrevista_auditoria after insert or update or delete on interno.fichas_entrevista
  for each row execute function interno.registrar_auditoria();

------------------------------------------------------------------------------
-- Recalcula todas as avaliações (mesma rotina que painel.listar_avaliacoes já faz) e diz quem é convocado
-- (AC ≥ 35 e RANK() ≤ vagas × 3 no Grupo/Nível — mesma regra de painel.listar_avaliacoes).
------------------------------------------------------------------------------
create or replace function interno.recalcular_todas() returns void
language plpgsql security definer set search_path = ''
as $$
declare r record;
begin
  for r in select x.id from publico.inscricoes x where x.status in ('submetida', 'aguardando_isencao', 'homologada')
  loop
    perform interno.calcular_avaliacao(r.id);
  end loop;
end;
$$;

create or replace function interno.eh_convocado(p_inscricao_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  with elegiveis as (
    select a.inscricao_id, i.grupo, i.nivel,
           rank() over (partition by i.grupo, i.nivel order by a.total desc) as posicao
    from interno.avaliacoes_curriculares a
    join publico.inscricoes i on i.id = a.inscricao_id
    where a.habilitado and a.total >= 35 and i.status in ('submetida', 'aguardando_isencao', 'homologada')
  )
  select coalesce((
    select e.posicao <= v.quantidade * 3
    from elegiveis e join interno.vagas v on v.grupo = e.grupo and v.nivel = e.nivel
    where e.inscricao_id = p_inscricao_id), false)
$$;
revoke execute on function interno.recalcular_todas(), interno.eh_convocado(uuid) from public, anon, authenticated;

------------------------------------------------------------------------------
-- Entrevista de um candidato: convocado?, fichas lançadas, ET e PF.
------------------------------------------------------------------------------
create or replace function painel.entrevista_do_candidato(p_inscricao_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_ac numeric;
  v_n integer;
  v_et numeric;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  perform interno.recalcular_todas();
  select a.total into v_ac from interno.avaliacoes_curriculares a where a.inscricao_id = p_inscricao_id;
  select count(*), round(avg(f.total), 2) into v_n, v_et from interno.fichas_entrevista f where f.inscricao_id = p_inscricao_id;
  return jsonb_build_object(
    'convocado', interno.eh_convocado(p_inscricao_id),
    'ac', v_ac,
    'n_fichas', v_n,
    'et', v_et,
    'pf', case when v_et is null then null else v_ac + v_et end,
    'banca_completa', v_n >= 3,
    'abaixo_do_corte', v_et is not null and v_et < 15,
    'fichas', coalesce((
      select jsonb_agg(to_jsonb(f) - 'lancado_por' order by f.created_at)
      from interno.fichas_entrevista f where f.inscricao_id = p_inscricao_id), '[]'::jsonb)
  );
end;
$$;

------------------------------------------------------------------------------
-- Lança (ou corrige) a ficha de UM avaliador. p_notas/p_justificativas: chaves dominio, analise,
-- planejamento, comunicacao, caso, postura. Justificativa obrigatória por competência (CLAUDE.md §8.6).
------------------------------------------------------------------------------
create or replace function painel.salvar_ficha_entrevista(
  p_inscricao_id uuid, p_avaliador text, p_notas jsonb, p_justificativas jsonb
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  k text;
  ks constant text[] := array['dominio', 'analise', 'planejamento', 'comunicacao', 'caso', 'postura'];
  teto constant integer[] := array[10, 10, 5, 5, 5, 5];
  v integer;
  j text;
  i integer;
  f interno.fichas_entrevista;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  perform interno.recalcular_todas();
  if not interno.eh_convocado(p_inscricao_id) then
    raise exception 'Só candidatos convocados para a entrevista (AC ≥ 35 e dentro de 3 por vaga) recebem ficha.' using errcode = 'P0001', hint = 'nao_convocado';
  end if;
  if char_length(btrim(coalesce(p_avaliador, ''))) < 3 then
    raise exception 'Informe o nome do avaliador.' using errcode = 'P0001', hint = 'avaliador_obrigatorio';
  end if;
  for i in 1..6 loop
    k := ks[i];
    begin v := (p_notas ->> k)::integer; exception when others then v := null; end;
    if v is null or v < 0 or v > teto[i] then
      raise exception 'Nota de "%" inválida: use um número inteiro de 0 a %.', k, teto[i] using errcode = 'P0001', hint = 'nota_invalida';
    end if;
    j := btrim(coalesce(p_justificativas ->> k, ''));
    if char_length(j) < 3 then
      raise exception 'Justificativa obrigatória para "%".', k using errcode = 'P0001', hint = 'justificativa_obrigatoria';
    end if;
  end loop;

  insert into interno.fichas_entrevista as x (
    inscricao_id, avaliador_nome,
    nota_dominio, nota_analise, nota_planejamento, nota_comunicacao, nota_caso, nota_postura,
    just_dominio, just_analise, just_planejamento, just_comunicacao, just_caso, just_postura, lancado_por)
  values (
    p_inscricao_id, btrim(p_avaliador),
    (p_notas ->> 'dominio')::int, (p_notas ->> 'analise')::int, (p_notas ->> 'planejamento')::int,
    (p_notas ->> 'comunicacao')::int, (p_notas ->> 'caso')::int, (p_notas ->> 'postura')::int,
    btrim(p_justificativas ->> 'dominio'), btrim(p_justificativas ->> 'analise'), btrim(p_justificativas ->> 'planejamento'),
    btrim(p_justificativas ->> 'comunicacao'), btrim(p_justificativas ->> 'caso'), btrim(p_justificativas ->> 'postura'),
    auth.uid())
  on conflict (inscricao_id, avaliador_nome) do update set
    nota_dominio = excluded.nota_dominio, nota_analise = excluded.nota_analise, nota_planejamento = excluded.nota_planejamento,
    nota_comunicacao = excluded.nota_comunicacao, nota_caso = excluded.nota_caso, nota_postura = excluded.nota_postura,
    just_dominio = excluded.just_dominio, just_analise = excluded.just_analise, just_planejamento = excluded.just_planejamento,
    just_comunicacao = excluded.just_comunicacao, just_caso = excluded.just_caso, just_postura = excluded.just_postura,
    lancado_por = auth.uid(), updated_at = now()
  returning * into f;
  return to_jsonb(f) - 'lancado_por';
end;
$$;

------------------------------------------------------------------------------
-- Remove uma ficha lançada por engano (exige motivo; o conteúdo apagado fica em interno.auditoria).
------------------------------------------------------------------------------
create or replace function painel.remover_ficha_entrevista(p_ficha_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 5 then
    raise exception 'Informe o motivo da remoção (mín. 5 caracteres).' using errcode = 'P0001', hint = 'motivo_obrigatorio';
  end if;
  insert into interno.auditoria (ator_id, ator_role, acao, entidade, entidade_id, dados_depois)
  values (auth.uid(), 'authenticated', 'MOTIVO_REMOCAO_FICHA', 'interno.fichas_entrevista', p_ficha_id::text,
          jsonb_build_object('motivo', btrim(p_motivo)));
  delete from interno.fichas_entrevista where id = p_ficha_id;
end;
$$;

------------------------------------------------------------------------------
-- Classificação (PF = AC + ET) por Grupo/Nível — só convocados. Desempate, nessa ordem (item 7.2):
--  I) idade ≥ 60 (mais velho primeiro)  II) maior nota da entrevista  III) maior pontuação em experiência
--  IV) maior total da AC  V) graduação mais antiga (data de colação)  VI) maior idade.
-- ASSUNÇÃO (pendente, ver docs/decisoes-pendentes.md): idade contada na data de encerramento das inscrições.
-- Posição só para quem tem ET e não está abaixo do corte de 15 (6.5.7). Devolve jsonb para não colidir com nomes.
------------------------------------------------------------------------------
create or replace function painel.classificacao_final(p_grupo publico.grupo_vaga default null, p_nivel publico.nivel_vaga default null)
returns setof jsonb
language plpgsql security definer set search_path = ''
as $$
declare ref date := (interno.encerramento() at time zone 'America/Sao_Paulo')::date;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  perform interno.recalcular_todas();
  return query
    with base as (
      select i.id as insc, c.nome, c.cpf, i.grupo, i.nivel, a.total as ac, a.pontos_experiencia as exp,
             i.data_colacao as colacao, c.data_nascimento as nasc,
             (extract(year from age(ref, c.data_nascimento)) >= 60) as idoso,
             (select count(*) from interno.fichas_entrevista f where f.inscricao_id = i.id) as n_fichas,
             (select round(avg(f.total), 2) from interno.fichas_entrevista f where f.inscricao_id = i.id) as et
      from publico.inscricoes i
      join publico.candidatos c on c.id = i.candidato_id
      join interno.avaliacoes_curriculares a on a.inscricao_id = i.id
      where interno.eh_convocado(i.id)
        and (p_grupo is null or i.grupo = p_grupo) and (p_nivel is null or i.nivel = p_nivel)
    ),
    calc as (
      select b.*, (b.ac + b.et) as pf, (b.et is not null and b.et < 15) as abaixo_corte
      from base b
    ),
    ranqueados as (
      select k.insc,
             rank() over (
               partition by k.grupo, k.nivel
               order by k.pf desc, k.idoso desc, case when k.idoso then k.nasc end asc,
                        k.et desc, k.exp desc, k.ac desc, k.colacao asc, k.nasc asc
             )::integer as posicao
      from calc k where k.et is not null and not k.abaixo_corte
    )
    select jsonb_build_object(
      'inscricao_id', k.insc, 'nome', k.nome, 'cpf', k.cpf, 'grupo', k.grupo, 'nivel', k.nivel,
      'ac', k.ac, 'et', k.et, 'pf', k.pf, 'n_fichas', k.n_fichas, 'banca_completa', k.n_fichas >= 3,
      'abaixo_do_corte', k.abaixo_corte, 'posicao', r.posicao)
    from calc k left join ranqueados r on r.insc = k.insc
    order by k.grupo, k.nivel, r.posicao nulls last, k.pf desc nulls last, k.nome;
end;
$$;

revoke execute on function painel.entrevista_do_candidato(uuid), painel.salvar_ficha_entrevista(uuid, text, jsonb, jsonb),
  painel.remover_ficha_entrevista(uuid, text), painel.classificacao_final(publico.grupo_vaga, publico.nivel_vaga) from public, anon;
grant execute on function painel.entrevista_do_candidato(uuid), painel.salvar_ficha_entrevista(uuid, text, jsonb, jsonb),
  painel.remover_ficha_entrevista(uuid, text), painel.classificacao_final(publico.grupo_vaga, publico.nivel_vaga) to authenticated;
