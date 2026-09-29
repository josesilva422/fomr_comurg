-- Minuta v9 do edital (Nº 001/2026, "Goiânia-GO, 05 de outubro de 2026"; arquivo de 29/09/2026 16h15), a pedido do
-- responsável em 29/09/2026. Só mudam DATAS; nenhuma regra de habilitação ou de pontuação mudou (conferido por diff do
-- texto completo contra o edital de 28/09):
--   * 4.3 inscrições de 05/10 a 20/10/2026 (era 28/09 a 13/10);
--   * Anexo IV item 4, pedidos de isenção até 14/10/2026 (era 06/10);
--   * 4.10.2 / Anexo IV item 9, pagamento após isenção indeferida até 23/10/2026, 23h59 (era 16/10);
--   * Anexo I, itens 1 e 2: títulos e cursos pontuam se concluídos até a PUBLICAÇÃO do edital — agora 05/10/2026;
--   * Anexo IV: os 24 itens com as datas novas.
-- As regras que usam o encerramento (18 anos, colação, laudo PcD — 3.1 e 10.5) leem interno.configuracao e se ajustam sozinhas.
-- Reversão: supabase/rollback/20260929170000_minuta_v9_publicacao_05_10.down.sql

update interno.configuracao set valor = to_jsonb('2026-10-05T00:00:00-03:00'::text), updated_at = now() where chave = 'inscricoes_abertura';
update interno.configuracao set valor = to_jsonb('2026-10-20T23:59:59-03:00'::text), updated_at = now() where chave = 'inscricoes_encerramento';
update interno.configuracao set valor = to_jsonb('2026-10-14T23:59:59-03:00'::text), updated_at = now() where chave = 'isencao_pedidos_fim';
update interno.configuracao set valor = to_jsonb('2026-10-23T23:59:59-03:00'::text), updated_at = now() where chave = 'isencao_pagamento_fim';

delete from interno.cronograma;
insert into interno.cronograma (ordem, evento, data_inicio, data_fim, detalhe) values
  (1,  'Publicação do Edital',                                                                                       null,         '2026-10-05', null),
  (2,  'Período para impugnação do Edital',                                                                          '2026-10-06', '2026-10-07', null),
  (3,  'Período de inscrições (inclusive)',                                                                          '2026-10-05', '2026-10-20', null),
  (4,  'Pedidos de isenção da taxa (no portal, no ato da inscrição)',                                                '2026-10-05', '2026-10-14', null),
  (5,  'Decisão sobre impugnações ao Edital',                                                                        null,         '2026-10-13', null),
  (6,  'Resultado dos pedidos de isenção',                                                                           null,         '2026-10-16', null),
  (7,  'Recurso contra indeferimento de isenção',                                                                    '2026-10-19', '2026-10-21', '19, 20 e 21/10/2026'),
  (8,  'Decisão dos recursos de isenção',                                                                            null,         '2026-10-22', null),
  (9,  'Pagamento da taxa pelos candidatos com isenção indeferida (item 4.10.2)',                                    null,         '2026-10-23', 'Até 23/10/2026, às 23h59'),
  (10, 'Homologação das inscrições (deferidas e indeferidas)',                                                       null,         '2026-10-27', null),
  (11, 'Recurso contra indeferimento de inscrição',                                                                  '2026-10-29', '2026-11-03', '29/10, 30/10 e 03/11/2026'),
  (12, 'Habilitação documental e análise curricular (simultâneas)',                                                  '2026-10-29', '2026-11-05', null),
  (13, 'Decisão dos recursos contra indeferimento de inscrição',                                                     null,         '2026-11-05', null),
  (14, 'Resultado preliminar — habilitação e análise curricular',                                                    null,         '2026-11-09', null),
  (15, 'Recurso contra habilitação e pontuação curricular',                                                          '2026-11-10', '2026-11-12', '10, 11 e 12/11/2026'),
  (16, 'Julgamento dos recursos',                                                                                    '2026-11-13', '2026-11-17', '13, 16 e 17/11/2026'),
  (17, 'Resultado definitivo da análise curricular + convocação para entrevista',                                    null,         '2026-11-18', null),
  (18, 'Entrevistas Técnicas Estruturadas',                                                                          '2026-11-19', '2026-11-30', null),
  (19, 'Heteroidentificação dos candidatos autodeclarados negros convocados para entrevista (na data da respectiva entrevista)', '2026-11-19', '2026-11-30', null),
  (20, 'Resultado preliminar das entrevistas, da heteroidentificação e classificação geral',                         null,         '2026-12-02', null),
  (21, 'Recurso contra resultado da entrevista, da heteroidentificação, das reservas de vagas e da classificação geral', '2026-12-03', '2026-12-07', '03, 04 e 07/12/2026'),
  (22, 'Julgamento dos recursos',                                                                                    '2026-12-08', '2026-12-10', '08, 09 e 10/12/2026'),
  (23, 'Resultado final do Processo Seletivo',                                                                       null,         '2026-12-11', null),
  (24, 'Homologação do resultado final',                                                                             null,         '2026-12-11', null);

-- Motor de regras: data de corte da publicação (Anexo I) e versão. Troca só a constante, os textos e a versão.
do $$
declare d text;
begin
  d := pg_get_functiondef('interno.calcular_avaliacao(uuid)'::regprocedure);
  if position('''2026-09-28''' in d) = 0 or position('(28/09/2026)' in d) = 0 or position('''v7-2026-09-25''' in d) = 0 then
    raise exception 'calcular_avaliacao: trechos esperados (data de publicação 28/09 e versão v7) não encontrados';
  end if;
  d := replace(d, '''2026-09-28''', '''2026-10-05''');
  d := replace(d, '(28/09/2026)', '(05/10/2026)');
  d := replace(d, '''v7-2026-09-25''', '''v8-2026-09-29''');
  execute d;
end;
$$;

-- Mensagem do prazo de isenção no verificador da inscrição.
do $$
declare d text;
begin
  d := pg_get_functiondef('publico.verificar_inscricao()'::regprocedure);
  if position('terminou em 06/10/2026' in d) = 0 then
    raise exception 'verificar_inscricao: mensagem do prazo de isenção não encontrada';
  end if;
  execute replace(d, 'terminou em 06/10/2026', 'terminou em 14/10/2026');
end;
$$;
