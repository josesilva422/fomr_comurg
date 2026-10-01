-- Heteroidentificação (item 10.4) e listas específicas de classificação para PcD e cota racial (itens
-- 10.1 e 10.2). O edital NÃO fixa percentual de PcD (só manda manter "lista específica de classificação");
-- a reserva de 20% para negros é aplicada "ao longo das convocações... mediante alternância e
-- proporcionalidade" — um processo contínuo e manual da Comissão, não uma fórmula fechada. Por isso o
-- sistema não decide quem ocupa a vaga reservada: só dá a lista ordenada de cada grupo (PcD / cota racial)
-- e o registro da heteroidentificação, que a Comissão aplica com o próprio julgamento, como o edital exige.
--
-- painel.classificacao_final ganha "cota_pcd" e "cota_racial" (de publico.inscricoes), para a tela filtrar
-- e numerar a lista específica de cada grupo sem recalcular nada no banco (a ordem já é a mesma do PF).
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
             coalesce(v.quantidade, 0) as vagas,
             coalesce(i.cota_pcd, false) as cota_pcd, coalesce(i.cota_racial, false) as cota_racial
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
      'abaixo_do_corte', k.abaixo_corte, 'posicao', r.posicao, 'vagas', k.vagas,
      'cota_pcd', k.cota_pcd, 'cota_racial', k.cota_racial)
    from calc k left join ranqueados r on r.insc = k.insc
    order by k.grupo, k.nivel, r.posicao nulls last, k.pf desc nulls last, k.nome;
end;
$$;

-- Registro da heteroidentificação (item 10.4): comissão específica, decisão sempre motivada. Só para
-- candidatos autodeclarados negros (cota_racial) e convocados para a entrevista (a heteroidentificação
-- ocorre na data da respectiva entrevista, Anexo IV item 19). Decisão pode ser refeita (ex.: recurso à
-- comissão recursal, item 10.4) — a linha é atualizada, não duplicada; tudo fica na auditoria.
create table interno.heteroidentificacoes (
  id uuid primary key default gen_random_uuid(),
  inscricao_id uuid not null unique references publico.inscricoes(id),
  decisao text not null check (decisao in ('confirmada', 'nao_confirmada')),
  decisao_motivada text not null,
  decidido_por uuid not null references interno.usuarios_internos(user_id),
  decidido_em timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table interno.heteroidentificacoes enable row level security;
-- Sem políticas: só acessível via as funções SECURITY DEFINER abaixo (padrão de interno.recursos).

create or replace function painel.registrar_heteroidentificacao(p_inscricao_id uuid, p_confirmada boolean, p_motivo text)
returns interno.heteroidentificacoes
language plpgsql
security definer
set search_path to ''
as $$
declare r interno.heteroidentificacoes; v_cota_racial boolean;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'A decisão da heteroidentificação precisa ser motivada (item 10.4; mínimo de 10 caracteres).'
      using errcode = 'P0001', hint = 'motivo_obrigatorio';
  end if;
  select i.cota_racial into v_cota_racial from publico.inscricoes i where i.id = p_inscricao_id;
  if v_cota_racial is null then
    raise exception 'Inscrição não encontrada.' using errcode = 'P0001', hint = 'nao_encontrada';
  end if;
  if not v_cota_racial then
    raise exception 'Este candidato não se autodeclarou negro; não cabe heteroidentificação.' using errcode = 'P0001', hint = 'nao_autodeclarado';
  end if;
  if not interno.eh_convocado(p_inscricao_id) then
    raise exception 'A heteroidentificação ocorre na data da entrevista (Anexo IV, item 19); este candidato ainda não foi convocado.'
      using errcode = 'P0001', hint = 'nao_convocado';
  end if;

  insert into interno.heteroidentificacoes (inscricao_id, decisao, decisao_motivada, decidido_por)
  values (p_inscricao_id, case when p_confirmada then 'confirmada' else 'nao_confirmada' end, btrim(p_motivo), auth.uid())
  on conflict (inscricao_id) do update
    set decisao = excluded.decisao, decisao_motivada = excluded.decisao_motivada,
        decidido_por = excluded.decidido_por, decidido_em = now()
  returning * into r;

  insert into interno.auditoria (ator_id, ator_role, acao, entidade, entidade_id, dados_depois)
  values (auth.uid(), 'authenticated', 'REGISTRAR_HETEROIDENTIFICACAO', 'interno.heteroidentificacoes', p_inscricao_id::text,
          jsonb_build_object('decisao', r.decisao, 'motivo', btrim(p_motivo)));
  return r;
end;
$$;

-- Lista os convocados autodeclarados negros, com a decisão (se já houver), para a tela da Comissão.
create or replace function painel.listar_heteroidentificacoes()
returns table(
  inscricao_id uuid, nome text, cpf text, grupo publico.grupo_vaga, nivel publico.nivel_vaga,
  decisao text, decisao_motivada text, decidido_em timestamptz, decidido_por text
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
    select i.id, c.nome, c.cpf, i.grupo, i.nivel, h.decisao, h.decisao_motivada, h.decidido_em, u.nome
    from publico.inscricoes i
    join publico.candidatos c on c.id = i.candidato_id
    left join interno.heteroidentificacoes h on h.inscricao_id = i.id
    left join interno.usuarios_internos u on u.user_id = h.decidido_por
    where i.cota_racial and interno.eh_convocado(i.id)
    order by (h.decisao is null) desc, c.nome;
end;
$$;
