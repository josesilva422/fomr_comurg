-- Cadastro de reserva (itens 2.1 e 11.1, minuta v11: 2 candidatos por vaga) e publicação do resultado final
-- (Anexo IV, item 23). O cadastro de reserva não precisa de tabela própria: é a mesma classificação final
-- (PF = AC + ET, painel.classificacao_final) já calculada, só dividida pela quantidade de vagas do
-- Grupo/Nível (interno.vagas) — 1ª até a Nª posição = vaga imediata, da (N+1)ª até a (3N)ª = cadastro de
-- reserva (3N é o mesmo teto usado para convocar para a entrevista, itens 6.4.4/6.5.1; por isso a reserva
-- é sempre exatamente 2N, batendo com "2 por vaga").
--
-- painel.classificacao_final ganha o campo "vagas" (join com interno.vagas) para a tela calcular a faixa.
create or replace function painel.classificacao_final(p_grupo publico.grupo_vaga default null::publico.grupo_vaga, p_nivel publico.nivel_vaga default null::publico.nivel_vaga)
returns setof jsonb
language plpgsql
security definer
set search_path to ''
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
             interno.media_entrevista(i.id) as et,
             coalesce(v.quantidade, 0) as vagas
      from publico.inscricoes i
      join publico.candidatos c on c.id = i.candidato_id
      join interno.avaliacoes_curriculares a on a.inscricao_id = i.id
      left join interno.vagas v on v.grupo = i.grupo and v.nivel = i.nivel
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
      'abaixo_do_corte', k.abaixo_corte, 'posicao', r.posicao, 'vagas', k.vagas)
    from calc k left join ranqueados r on r.insc = k.insc
    order by k.grupo, k.nivel, r.posicao nulls last, k.pf desc nulls last, k.nome;
end;
$$;

-- Publica o resultado final (Anexo IV, item 23) de UM candidato convocado: classificado na vaga imediata,
-- no cadastro de reserva, eliminado na entrevista (item 6.5.7) ou não classificado (fora da faixa de 3
-- vezes as vagas). Exige a banca completa (>= 3 fichas, item 6.5.2).
create or replace function painel.publicar_resultado_final(p_inscricao_id uuid, p_justificativa text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_grupo publico.grupo_vaga; v_nivel publico.nivel_vaga;
  v jsonb;
  v_posicao integer; v_vagas integer; v_pf numeric; v_bancacompleta boolean; v_abaixo boolean; v_nfichas integer;
  v_situacao text; v_motivacao text;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_justificativa, ''))) < 5 then
    raise exception 'Informe a justificativa da publicação.' using errcode = 'P0001', hint = 'justificativa_obrigatoria';
  end if;

  select i.grupo, i.nivel into v_grupo, v_nivel from publico.inscricoes i where i.id = p_inscricao_id;
  if v_grupo is null then
    raise exception 'Inscrição não encontrada ou não convocada para a entrevista.' using errcode = 'P0001', hint = 'nao_encontrada';
  end if;

  select x into v from painel.classificacao_final(v_grupo, v_nivel) x where x ->> 'inscricao_id' = p_inscricao_id::text;
  if v is null then
    raise exception 'Inscrição não encontrada ou não convocada para a entrevista.' using errcode = 'P0001', hint = 'nao_encontrada';
  end if;

  v_nfichas := (v ->> 'n_fichas')::integer;
  v_bancacompleta := (v ->> 'banca_completa')::boolean;
  v_abaixo := (v ->> 'abaixo_do_corte')::boolean;
  v_posicao := (v ->> 'posicao')::integer;
  v_vagas := (v ->> 'vagas')::integer;
  v_pf := (v ->> 'pf')::numeric;

  if not v_abaixo and not v_bancacompleta then
    raise exception 'A banca de entrevista deste candidato ainda não tem as 3 fichas mínimas (item 6.5.2).'
      using errcode = 'P0001', hint = 'banca_incompleta';
  end if;

  if v_abaixo then
    v_situacao := 'eliminado na entrevista técnica';
    v_motivacao := 'Nota da entrevista abaixo de 15 pontos (item 6.5.7).';
  elsif v_posicao is null then
    v_situacao := 'não classificado';
    v_motivacao := null;
  elsif v_posicao <= v_vagas then
    v_situacao := 'classificado';
    v_motivacao := null;
  elsif v_posicao <= v_vagas * 3 then
    v_situacao := 'cadastro de reserva';
    v_motivacao := null;
  else
    v_situacao := 'não classificado';
    v_motivacao := null;
  end if;

  insert into publico.resultados_candidato (inscricao_id, etapa, pontuacao, posicao, situacao, motivacao, publicado_por)
  values (p_inscricao_id, 'resultado_final', v_pf, v_posicao, v_situacao, v_motivacao, auth.uid())
  on conflict (inscricao_id, etapa) do update
    set pontuacao = excluded.pontuacao, posicao = excluded.posicao, situacao = excluded.situacao,
        motivacao = excluded.motivacao, publicado_por = excluded.publicado_por, publicado_em = now();

  insert into interno.auditoria (ator_id, ator_role, acao, entidade, entidade_id, dados_depois)
  values (auth.uid(), 'authenticated', 'PUBLICAR_RESULTADO', 'publico.resultados_candidato', p_inscricao_id::text,
          jsonb_build_object('etapa', 'resultado_final', 'situacao', v_situacao, 'pontuacao', v_pf, 'posicao', v_posicao,
                              'justificativa', btrim(p_justificativa)));
end;
$$;

-- Publica em lote todos os convocados com banca completa de um Grupo/Nível.
create or replace function painel.publicar_resultados_final_lote(p_grupo publico.grupo_vaga, p_nivel publico.nivel_vaga, p_justificativa text)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare r jsonb; v_qtd integer := 0;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  for r in select * from painel.classificacao_final(p_grupo, p_nivel)
  loop
    if (r ->> 'banca_completa')::boolean or (r ->> 'abaixo_do_corte')::boolean then
      perform painel.publicar_resultado_final((r ->> 'inscricao_id')::uuid, p_justificativa);
      v_qtd := v_qtd + 1;
    end if;
  end loop;
  return v_qtd;
end;
$$;

-- Visão da Comissão sobre o que já foi publicado do resultado final.
create or replace function painel.publicacoes_final()
returns table(
  inscricao_id uuid, pontuacao numeric, posicao integer, situacao text, motivacao text,
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
    select r.inscricao_id, r.pontuacao, r.posicao, r.situacao, r.motivacao, r.publicado_em, u.nome
    from publico.resultados_candidato r
    left join interno.usuarios_internos u on u.user_id = r.publicado_por
    where r.etapa = 'resultado_final';
end;
$$;
