-- Etapa de publicação (CLAUDE.md, seção 6; edital itens 7.3, 13.2 e 13.3): quando o gestor aprova e publica,
-- o sistema copia para publico.resultados_candidato só o que o candidato pode ver (pontuação por etapa,
-- posição, situação e motivação). Esta migração cobre as duas publicações da análise curricular do
-- Anexo IV: item 14 (resultado preliminar) e item 17 (resultado definitivo + convocação, 6.4.4/6.5.1).
-- As publicações da entrevista técnica e do resultado final (itens 20 e 23) ficam para quando essas
-- etapas chegarem (seção 12, Fases 3/4) — mesma tabela, etapas 'entrevista_preliminar'/'resultado_final'.

create table publico.resultados_candidato (
  id uuid primary key default gen_random_uuid(),
  inscricao_id uuid not null references publico.inscricoes(id),
  etapa text not null check (etapa in ('ac_preliminar', 'ac_definitivo', 'entrevista_preliminar', 'resultado_final')),
  pontuacao numeric,
  posicao integer,
  situacao text not null,
  motivacao text,
  publicado_por uuid not null references interno.usuarios_internos(user_id),
  publicado_em timestamptz not null default now(),
  unique (inscricao_id, etapa)
);

alter table publico.resultados_candidato enable row level security;

grant select on publico.resultados_candidato to authenticated;

create policy resultados_candidato_select_propria on publico.resultados_candidato
  for select to authenticated
  using (inscricao_id = (select publico.minha_inscricao_id()));

-- Publica (ou republica, ex.: após julgamento de recurso) o resultado da análise curricular de UMA inscrição.
-- Só inscrições homologadas (Anexo IV item 10 já concluído). p_etapa: 'ac_preliminar' (item 14) ou
-- 'ac_definitivo' (item 17, inclui a convocação dos itens 6.4.4/6.5.1).
create or replace function painel.publicar_resultado_ac(p_inscricao_id uuid, p_etapa text, p_justificativa text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_grupo publico.grupo_vaga;
  v_nivel publico.nivel_vaga;
  v_status publico.status_inscricao;
  v_hab boolean;
  v_motivos jsonb;
  v_total numeric;
  v_vagas integer;
  v_posicao integer;
  v_convocado boolean;
  v_situacao text;
  v_motivacao text;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if p_etapa not in ('ac_preliminar', 'ac_definitivo') then
    raise exception 'Etapa inválida.' using errcode = 'P0001', hint = 'etapa_invalida';
  end if;
  if char_length(btrim(coalesce(p_justificativa, ''))) < 5 then
    raise exception 'Informe a justificativa da publicação.' using errcode = 'P0001', hint = 'justificativa_obrigatoria';
  end if;

  perform interno.calcular_avaliacao(p_inscricao_id);

  select i.grupo, i.nivel, i.status into v_grupo, v_nivel, v_status
    from publico.inscricoes i where i.id = p_inscricao_id;
  if v_status is null then
    raise exception 'Inscrição não encontrada.' using errcode = 'P0001', hint = 'nao_encontrada';
  end if;
  if v_status <> 'homologada' then
    raise exception 'Só é possível publicar o resultado de uma inscrição homologada (Anexo IV, item 10).'
      using errcode = 'P0001', hint = 'nao_homologada';
  end if;

  select a.habilitado, a.motivos, a.total into v_hab, v_motivos, v_total
    from interno.avaliacoes_curriculares a where a.inscricao_id = p_inscricao_id;

  select v.quantidade into v_vagas from interno.vagas v where v.grupo = v_grupo and v.nivel = v_nivel;

  select e.posicao into v_posicao
    from (
      select i.id, rank() over (partition by i.grupo, i.nivel order by a.total desc)::integer as posicao
      from publico.inscricoes i
      join interno.avaliacoes_curriculares a on a.inscricao_id = i.id
      where i.status = 'homologada' and i.grupo = v_grupo and i.nivel = v_nivel
        and a.habilitado and a.total >= 35
    ) e
    where e.id = p_inscricao_id;

  v_convocado := v_hab and v_posicao is not null and v_posicao <= (coalesce(v_vagas, 0) * 3);

  if not v_hab then
    v_situacao := 'inabilitado';
    select string_agg(m, '; ') into v_motivacao from jsonb_array_elements_text(coalesce(v_motivos, '[]'::jsonb)) m;
  elsif p_etapa = 'ac_definitivo' then
    v_situacao := case when v_convocado then 'convocado para a entrevista técnica' else 'habilitado, não convocado para a entrevista técnica' end;
    v_motivacao := null;
  else
    v_situacao := 'habilitado';
    v_motivacao := null;
  end if;

  insert into publico.resultados_candidato (inscricao_id, etapa, pontuacao, posicao, situacao, motivacao, publicado_por)
  values (p_inscricao_id, p_etapa, v_total, v_posicao, v_situacao, v_motivacao, auth.uid())
  on conflict (inscricao_id, etapa) do update
    set pontuacao = excluded.pontuacao, posicao = excluded.posicao, situacao = excluded.situacao,
        motivacao = excluded.motivacao, publicado_por = excluded.publicado_por, publicado_em = now();

  insert into interno.auditoria (ator_id, ator_role, acao, entidade, entidade_id, dados_depois)
  values (auth.uid(), 'authenticated', 'PUBLICAR_RESULTADO', 'publico.resultados_candidato', p_inscricao_id::text,
          jsonb_build_object('etapa', p_etapa, 'situacao', v_situacao, 'pontuacao', v_total, 'posicao', v_posicao,
                              'justificativa', btrim(p_justificativa)));
end;
$$;

-- Publica em lote (ex.: todos os homologados de um Grupo/Nível de uma vez). Mesma regra e auditoria do
-- publicar_resultado_ac, uma linha de auditoria por inscrição.
create or replace function painel.publicar_resultados_ac_lote(
  p_etapa text, p_grupo publico.grupo_vaga, p_nivel publico.nivel_vaga, p_justificativa text
)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  r record;
  v_qtd integer := 0;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  for r in
    select i.id from publico.inscricoes i
    where i.status = 'homologada' and i.grupo = p_grupo and i.nivel = p_nivel
  loop
    perform painel.publicar_resultado_ac(r.id, p_etapa, p_justificativa);
    v_qtd := v_qtd + 1;
  end loop;
  return v_qtd;
end;
$$;

-- Visão da Comissão sobre o que já foi publicado (para a tela de publicação mostrar o estado atual).
create or replace function painel.publicacoes_ac()
returns table(
  inscricao_id uuid, etapa text, pontuacao numeric, posicao integer, situacao text, motivacao text,
  publicado_em timestamptz, publicado_por text
)
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select r.inscricao_id, r.etapa, r.pontuacao, r.posicao, r.situacao, r.motivacao, r.publicado_em, u.nome
    from publico.resultados_candidato r
    left join interno.usuarios_internos u on u.user_id = r.publicado_por
    where r.etapa in ('ac_preliminar', 'ac_definitivo');
end;
$$;
