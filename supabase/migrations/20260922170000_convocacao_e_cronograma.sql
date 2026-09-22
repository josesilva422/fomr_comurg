-- Fase 3 (início) · Convocação para entrevista (edital itens 6.4.4 e 6.5.1) e Cronograma do certame
-- (Anexo IV), a pedido do responsável em 22/09/2026, depois do edital atualizado ("22-09-2026-08-07")
-- ter mudado a convocação de até 5 para até 3 candidatos por vaga e antecipado as datas de entrevista/
-- recurso/resultado final. Guarda os dados de vagas e cronograma no banco (não hardcoded no front),
-- e expõe os dois pelo schema `painel` (só para quem está em interno.usuarios_internos).
--
-- Continua tudo em RASCUNHO: nenhuma lista de convocação é publicada ao candidato aqui — isso é a Fase 3
-- completa (etapa de publicação), fora do escopo de hoje (CLAUDE.md, princípio 2).
-- Reversão: supabase/rollback/20260922170000_convocacao_e_cronograma.down.sql

------------------------------------------------------------------------------
-- Vagas por Grupo e Nível (edital, item 2.1) — hoje hardcoded em CLAUDE.md 8.7, agora também no banco
-- para o cálculo da convocação (vagas × 3, item 6.5.1).
------------------------------------------------------------------------------
create table interno.vagas (
  grupo       publico.grupo_vaga not null,
  nivel       publico.nivel_vaga not null,
  quantidade  integer not null check (quantidade > 0),
  remuneracao numeric(10,2) not null,
  primary key (grupo, nivel)
);
alter table interno.vagas enable row level security;
revoke all on interno.vagas from public, anon, authenticated;

insert into interno.vagas (grupo, nivel, quantidade, remuneracao) values
  ('A', 'junior', 1, 8000),
  ('A', 'pleno',  1, 11000),
  ('A', 'senior', 1, 15000),
  ('B', 'junior', 1, 8000),
  ('B', 'pleno',  2, 11000),
  ('B', 'senior', 1, 15000),
  ('C', 'junior', 1, 8000),
  ('C', 'pleno',  1, 11000),
  ('C', 'senior', 1, 15000);

------------------------------------------------------------------------------
-- Cronograma do certame (Anexo IV) — "ordem" é o mesmo número de item do Anexo IV, para rastreabilidade.
-- Datas conferidas contra o edital atualizado em 22/09/2026 (itens 12 a 18 foram antecipados nessa
-- revisão; itens 1 a 11 não mudaram). data_inicio/data_fim nulos cobrem eventos "até X" ou "a partir de X".
------------------------------------------------------------------------------
create table interno.cronograma (
  ordem       integer primary key,
  evento      text not null,
  data_inicio date,
  data_fim    date,
  detalhe     text,  -- texto livre quando as datas não formam um intervalo contínuo (ex.: recursos em 3 dias específicos)
  check (data_inicio is not null or data_fim is not null)
);
alter table interno.cronograma enable row level security;
revoke all on interno.cronograma from public, anon, authenticated;

insert into interno.cronograma (ordem, evento, data_inicio, data_fim, detalhe) values
  (1,  'Publicação do Edital',                                                  null,         '2026-09-24', null),
  (2,  'Período para impugnação do Edital',                                     '2026-09-25', '2026-09-26', null),
  (3,  'Período de inscrições + pedidos de isenção da taxa',                    '2026-09-24', '2026-10-07', null),
  (4,  'Resposta aos pedidos de isenção da taxa',                               null,         '2026-10-09', null),
  (5,  'Decisão sobre impugnações ao Edital',                                   null,         '2026-10-09', null),
  (6,  'Homologação das inscrições',                                           null,         '2026-10-13', null),
  (7,  'Habilitação documental e análise curricular (simultâneas)',            '2026-10-14', '2026-10-20', null),
  (8,  'Resultado preliminar — habilitação e análise curricular',              null,         '2026-10-22', null),
  (9,  'Recurso contra habilitação e pontuação curricular',                    '2026-10-23', '2026-10-27', '23, 24 e 27/10/2026'),
  (10, 'Julgamento dos recursos',                                              '2026-10-28', '2026-10-30', '28, 29 e 30/10/2026'),
  (11, 'Resultado definitivo análise curricular + convocação para entrevista', null,         '2026-10-31', null),
  (12, 'Entrevistas Técnicas Estruturadas',                                    '2026-11-03', '2026-11-12', null),
  (13, 'Resultado preliminar das entrevistas e classificação geral',           null,         '2026-11-14', null),
  (14, 'Recurso contra resultado da entrevista',                               '2026-11-17', '2026-11-19', '17, 18 e 19/11/2026'),
  (15, 'Julgamento dos recursos',                                              '2026-11-20', '2026-11-24', '20, 21 e 24/11/2026'),
  (16, 'Resultado final do Processo Seletivo',                                 null,         '2026-11-25', null),
  (17, 'Homologação do resultado final',                                       null,         '2026-11-25', null),
  (18, 'Início das convocações',                                               '2026-11-26', null,         'a partir de 26/11/2026');

------------------------------------------------------------------------------
-- painel.listar_avaliacoes(): ganha posicao/vagas/convocado (itens 6.4.4 e 6.5.1).
-- "convocado" = habilitado, AC ≥ 35 (6.4.4) e RANK() <= vagas × 3 dentro do Grupo/Nível — RANK() (não
-- DENSE_RANK nem ROW_NUMBER) inclui automaticamente quem empata na última posição, como o edital exige.
------------------------------------------------------------------------------
drop function if exists painel.listar_avaliacoes();
create function painel.listar_avaliacoes()
returns table (
  inscricao_id uuid, nome text, cpf text, email text, telefone text,
  grupo publico.grupo_vaga, nivel publico.nivel_vaga, status publico.status_inscricao,
  habilitado boolean, motivos jsonb,
  pontos_formacao numeric, pontos_cursos numeric, pontos_experiencia numeric, total numeric,
  submetida_em timestamptz, calculado_em timestamptz,
  posicao integer, vagas integer, convocado boolean
)
language plpgsql security definer set search_path = ''
as $$
declare r record;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  for r in select x.id from publico.inscricoes x where x.status in ('submetida', 'aguardando_isencao', 'homologada')
  loop
    perform interno.calcular_avaliacao(r.id);
  end loop;
  return query
    with base as (
      select i.id, c.nome, c.cpf, c.email, c.telefone, i.grupo, i.nivel, i.status,
             a.habilitado, a.motivos, a.pontos_formacao, a.pontos_cursos, a.pontos_experiencia, a.total,
             i.submetida_em, a.calculado_em,
             coalesce(v.quantidade, 0) as vagas
      from publico.inscricoes i
      join publico.candidatos c on c.id = i.candidato_id
      join interno.avaliacoes_curriculares a on a.inscricao_id = i.id
      left join interno.vagas v on v.grupo = i.grupo and v.nivel = i.nivel
      where i.status in ('submetida', 'aguardando_isencao', 'homologada')
    ),
    elegiveis as (
      -- item 6.4.4: só quem é habilitado e atinge 35 pts entra na disputa por convocação
      -- (colunas qualificadas com "base." porque habilitado/total/grupo/nivel são também parâmetros OUT
      -- da função — sem o prefixo, o Postgres não sabe se é a coluna da CTE ou a variável da função)
      select base.id, rank() over (partition by base.grupo, base.nivel order by base.total desc)::integer as posicao
      from base
      where base.habilitado and base.total >= 35
    )
    select b.id, b.nome, b.cpf, b.email, b.telefone, b.grupo, b.nivel, b.status,
           b.habilitado, b.motivos, b.pontos_formacao, b.pontos_cursos, b.pontos_experiencia, b.total,
           b.submetida_em, b.calculado_em,
           e.posicao, b.vagas,
           coalesce(e.posicao <= (b.vagas * 3), false) as convocado -- item 6.5.1: até 3 candidatos por vaga
    from base b
    left join elegiveis e on e.id = b.id
    order by b.grupo, b.nivel, b.total desc nulls last;
end;
$$;

------------------------------------------------------------------------------
-- painel.listar_cronograma(): datas do Anexo IV, só para a Comissão.
------------------------------------------------------------------------------
create or replace function painel.listar_cronograma()
returns table (ordem integer, evento text, data_inicio date, data_fim date, detalhe text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query select c.ordem, c.evento, c.data_inicio, c.data_fim, c.detalhe from interno.cronograma c order by c.ordem;
end;
$$;

revoke execute on function painel.listar_avaliacoes(), painel.listar_cronograma() from public, anon;
grant execute on function painel.listar_avaliacoes(), painel.listar_cronograma() to authenticated;
