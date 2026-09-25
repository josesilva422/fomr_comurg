-- Comprovante de experiência obrigatório por vínculo (pedido do responsável, 25/09/2026 — revoga a parte de experiência
-- da decisão de 22/09/2026, migração 20260922140000). O edital exige COMPROVAR a experiência (3.1, alínea e) pelos
-- documentos do item 5.3 (e Anexo III); documento ausente não é considerado (5.5.1).
--
-- Regra de "vínculo comprovado" (só presença do documento; a validade — timbrado, carimbo, assinatura, período,
-- atividades — continua sendo conferida pela Comissão):
--   privado  (5.3.1): CTPS, declaração do empregador OU contrato — um deles, isoladamente ou em combinação;
--   público  (5.3.2): certidão/declaração do órgão OU contrato administrativo/instrumento equivalente;
--   autônomo (5.3.3): contrato, RPA ou nota fiscal E declaração do contratante ("acompanhado de").
--   ART/RRT/acervo (5.3.5) e declaração de liderança (5.3.4) complementam, mas não comprovam o vínculo sozinhos.
--
-- O que muda:
--   * interno.vinculo_comprovado(uuid): a regra acima, num lugar só;
--   * publico.verificar_inscricao(): pendência BLOQUEANTE "vinculo_sem_comprovante" por vínculo (etapa 4);
--   * interno.meses_experiencia_uniao(): só soma vínculos comprovados (habilitação e pontuação, Anexo I item 3);
--   * interno.calcular_avaliacao(): detalhamento informa quantos vínculos ficaram de fora; versão v6-2026-09-25.
-- Reversão: supabase/rollback/20260925110000_comprovante_experiencia_obrigatorio.down.sql

create or replace function interno.vinculo_comprovado(p_vinculo_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case v.tipo
    when 'privado' then exists (
      select 1 from publico.documentos d where d.vinculo_id = v.id and d.ativo
        and d.tipo in ('experiencia_ctps', 'experiencia_declaracao', 'experiencia_contrato'))
    when 'publico' then exists (
      select 1 from publico.documentos d where d.vinculo_id = v.id and d.ativo
        and d.tipo in ('experiencia_publica', 'experiencia_contrato'))
    when 'autonomo' then
      exists (select 1 from publico.documentos d where d.vinculo_id = v.id and d.ativo and d.tipo = 'experiencia_autonomo')
      and exists (select 1 from publico.documentos d where d.vinculo_id = v.id and d.ativo and d.tipo = 'experiencia_declaracao')
  end
  from publico.vinculos_declarados v
  where v.id = p_vinculo_id
$$;
revoke execute on function interno.vinculo_comprovado(uuid) from public, anon, authenticated;

------------------------------------------------------------------------------
-- União de meses (5.4.1/5.4.2) só com vínculos comprovados.
------------------------------------------------------------------------------
create or replace function interno.meses_experiencia_uniao(p_inscricao_id uuid)
returns integer
language sql stable security definer set search_path = ''
as $$
  with encerramento_mes as (
    select (extract(year from d)::int * 12 + extract(month from d)::int - 1) as m
    from (select (interno.encerramento() at time zone 'America/Sao_Paulo')::date as d) x
  ),
  base as (
    select
      (extract(year from v.inicio)::int * 12 + extract(month from v.inicio)::int - 1) as ini,
      case when v.ativo then (select m from encerramento_mes)
           else (extract(year from v.fim)::int * 12 + extract(month from v.fim)::int - 1) end as fim
    from publico.vinculos_declarados v
    where v.inscricao_id = p_inscricao_id
      and interno.vinculo_comprovado(v.id) -- 3.1 "comprovar", 5.3 e 5.5.1: vínculo sem comprovante não conta
  ),
  validos as (
    select ini, fim from base where fim >= ini
  ),
  com_anterior as (
    select ini, fim,
           max(fim) over (order by ini, fim rows between unbounded preceding and 1 preceding) as fim_max_ant
    from validos
  ),
  grupos as (
    select ini, fim,
           sum(case when fim_max_ant is null or ini > fim_max_ant + 1 then 1 else 0 end) over (order by ini, fim) as grp
    from com_anterior
  )
  select coalesce(sum(mx - mn + 1), 0)::int
  from (select grp, min(ini) as mn, max(fim) as mx from grupos group by grp) t
$$;
revoke execute on function interno.meses_experiencia_uniao(uuid) from public, anon, authenticated;

------------------------------------------------------------------------------
-- Pendência bloqueante por vínculo sem comprovante (troca de texto na função existente; erro se o trecho sumir).
------------------------------------------------------------------------------
do $$
declare d text; ancora text;
begin
  d := pg_get_functiondef('publico.verificar_inscricao()'::regprocedure);

  ancora := '  -- 4 · experiência (o documento por vínculo não é exigido para enviar nem para pontuar — a pontuação de
  -- experiência é por tempo total comprovado, não por item; ver interno.calcular_avaliacao)';
  if position(ancora in d) = 0 then raise exception 'verificar_inscricao: comentário da etapa 4 não encontrado'; end if;
  d := replace(d, ancora,
'  -- 4 · experiência: cada vínculo precisa do comprovante do item 5.3 (decisão do responsável, 25/09/2026 — ver
  -- interno.vinculo_comprovado); vínculo sem comprovante também não conta no cálculo (interno.meses_experiencia_uniao)');

  ancora := '  if i.nivel = ''senior''
     and not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = ''declaracao_lideranca'') then';
  if position(ancora in d) = 0 then raise exception 'verificar_inscricao: bloco de liderança não encontrado'; end if;
  d := replace(d, ancora,
'  for r in
    select v.empregador_contratante, v.tipo from publico.vinculos_declarados v
    where v.inscricao_id = i.id and not interno.vinculo_comprovado(v.id)
    order by v.inicio
  loop
    return query select ''vinculo_sem_comprovante''::text,
      format(''Anexe o comprovante do vínculo com "%s": %s'', r.empregador_contratante,
        case r.tipo
          when ''privado'' then ''CTPS, declaração do empregador ou contrato.''
          when ''publico'' then ''certidão ou declaração do órgão, ou contrato administrativo.''
          else ''contrato, RPA ou nota fiscal, junto com a declaração do contratante.'' end), 4, true;
  end loop;
' || ancora);
  execute d;
end;
$$;

------------------------------------------------------------------------------
-- Motor: informa os vínculos sem comprovante no detalhamento e nos avisos; versão v6.
------------------------------------------------------------------------------
do $$
declare d text; ancora text;
begin
  d := pg_get_functiondef('interno.calcular_avaliacao(uuid)'::regprocedure);

  ancora := '''experiencia'', jsonb_build_object(''minimo_meses'', minimo_meses,';
  if position(ancora in d) = 0 then raise exception 'calcular_avaliacao: detalhamento de experiência não encontrado'; end if;
  d := replace(d, ancora,
    '''experiencia'', jsonb_build_object(''vinculos_sem_comprovante'', (select count(*) from publico.vinculos_declarados v where v.inscricao_id = p_inscricao_id and not interno.vinculo_comprovado(v.id)), ''minimo_meses'', minimo_meses,');

  ancora := '— o resultado não depende da ordem dos itens.''';
  if position(ancora in d) = 0 then raise exception 'calcular_avaliacao: último aviso não encontrado'; end if;
  d := replace(d, ancora, ancora || ',
        ''Experiência: só contam os vínculos com o comprovante do item 5.3 anexado (privado: CTPS, declaração ou contrato; público: certidão/declaração do órgão ou contrato administrativo; autônomo: contrato/RPA/nota fiscal + declaração do contratante). A validade do documento e a área da experiência são conferidas pela Comissão.''');

  if position('''v5-2026-09-25''' in d) = 0 then raise exception 'calcular_avaliacao: versão v5 não encontrada'; end if;
  d := replace(d, '''v5-2026-09-25''', '''v6-2026-09-25''');
  execute d;
end;
$$;

select interno.recalcular_todas();
