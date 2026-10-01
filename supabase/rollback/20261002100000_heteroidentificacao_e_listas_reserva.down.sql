drop function if exists painel.listar_heteroidentificacoes();
drop function if exists painel.registrar_heteroidentificacao(uuid, boolean, text);
drop table if exists interno.heteroidentificacoes;

-- Volta classificacao_final ao formato de 20261001240000_publicacao_resultado_final.sql (sem cota_pcd/cota_racial).
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
