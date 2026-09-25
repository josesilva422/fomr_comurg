-- Volta ao estado da migração 20260925100000: comprovante por vínculo não é exigido nem filtra a contagem.

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

do $$
declare d text; ini int; fim int;
begin
  d := pg_get_functiondef('publico.verificar_inscricao()'::regprocedure);
  d := replace(d,
'  -- 4 · experiência: cada vínculo precisa do comprovante do item 5.3 (decisão do responsável, 25/09/2026 — ver
  -- interno.vinculo_comprovado); vínculo sem comprovante também não conta no cálculo (interno.meses_experiencia_uniao)',
'  -- 4 · experiência (o documento por vínculo não é exigido para enviar nem para pontuar — a pontuação de
  -- experiência é por tempo total comprovado, não por item; ver interno.calcular_avaliacao)');
  ini := position('  for r in
    select v.empregador_contratante, v.tipo' in d);
  fim := position('  end loop;
  if i.nivel = ''senior''' in d);
  if ini = 0 or fim = 0 then raise exception 'verificar_inscricao: bloco do comprovante não encontrado'; end if;
  d := left(d, ini - 1) || substr(d, fim + length('  end loop;
'));
  execute d;

  d := pg_get_functiondef('interno.calcular_avaliacao(uuid)'::regprocedure);
  d := replace(d, '''vinculos_sem_comprovante'', (select count(*) from publico.vinculos_declarados v where v.inscricao_id = p_inscricao_id and not interno.vinculo_comprovado(v.id)), ', '');
  d := replace(d, ',
        ''Experiência: só contam os vínculos com o comprovante do item 5.3 anexado (privado: CTPS, declaração ou contrato; público: certidão/declaração do órgão ou contrato administrativo; autônomo: contrato/RPA/nota fiscal + declaração do contratante). A validade do documento e a área da experiência são conferidas pela Comissão.''', '');
  d := replace(d, '''v6-2026-09-25''', '''v5-2026-09-25''');
  execute d;
end;
$$;

drop function interno.vinculo_comprovado(uuid);
select interno.recalcular_todas();
