-- Edital PUBLICADO (Nº 001/2026, "Goiânia-GO, 28 de setembro de 2026"), recebido em 24/09/2026. Diferenças de datas:
--   publicação 28/09 (era 24/09) · inscrições 28/09 a 13/10 (era 24/09 a 07/10) · cronograma agora com 24 itens.
-- Este arquivo só ajusta DADOS e a data de corte do motor. Mudanças de REGRA do edital (isenção 4.10.2, diploma digital
-- 5.1.2, recursos por e-mail 9.2, reservas 10.1/10.2/11.1) estão em docs/decisoes-pendentes.md.
-- Reversão: supabase/rollback/20260924110000_edital_publicado_28_09.down.sql

update interno.configuracao set valor = to_jsonb('2026-09-28T00:00:00-03:00'::text), updated_at = now() where chave = 'inscricoes_abertura';
update interno.configuracao set valor = to_jsonb('2026-10-13T23:59:59-03:00'::text), updated_at = now() where chave = 'inscricoes_encerramento';

delete from interno.cronograma;
insert into interno.cronograma (ordem, evento, data_inicio, data_fim, detalhe) values
  (1,  'Publicação do Edital',                                                                                       null,         '2026-09-28', null),
  (2,  'Período para impugnação do Edital',                                                                          '2026-09-29', '2026-09-30', null),
  (3,  'Período de inscrições (inclusive)',                                                                          '2026-09-28', '2026-10-13', null),
  (4,  'Pedidos de isenção da taxa (no portal, no ato da inscrição)',                                                '2026-09-28', '2026-10-06', null),
  (5,  'Decisão sobre impugnações ao Edital',                                                                        null,         '2026-10-05', null),
  (6,  'Resultado dos pedidos de isenção',                                                                           null,         '2026-10-08', null),
  (7,  'Recurso contra indeferimento de isenção',                                                                    '2026-10-09', '2026-10-14', '09, 13 e 14/10/2026'),
  (8,  'Decisão dos recursos de isenção',                                                                            null,         '2026-10-15', null),
  (9,  'Pagamento da taxa pelos candidatos com isenção indeferida (item 4.10.2)',                                    null,         '2026-10-16', 'Até 16/10/2026, às 23h59'),
  (10, 'Homologação das inscrições (deferidas e indeferidas)',                                                       null,         '2026-10-20', null),
  (11, 'Recurso contra indeferimento de inscrição',                                                                  '2026-10-21', '2026-10-23', '21, 22 e 23/10/2026'),
  (12, 'Habilitação documental e análise curricular (simultâneas)',                                                  '2026-10-21', '2026-10-27', null),
  (13, 'Decisão dos recursos contra indeferimento de inscrição',                                                     null,         '2026-10-27', null),
  (14, 'Resultado preliminar — habilitação e análise curricular',                                                    null,         '2026-10-30', null),
  (15, 'Recurso contra habilitação e pontuação curricular',                                                          '2026-11-03', '2026-11-05', '03, 04 e 05/11/2026'),
  (16, 'Julgamento dos recursos',                                                                                    '2026-11-06', '2026-11-10', '06, 09 e 10/11/2026'),
  (17, 'Resultado definitivo da análise curricular + convocação para entrevista',                                    null,         '2026-11-11', null),
  (18, 'Entrevistas Técnicas Estruturadas',                                                                          '2026-11-12', '2026-11-23', null),
  (19, 'Heteroidentificação dos candidatos autodeclarados negros convocados para entrevista (na data da respectiva entrevista)', '2026-11-12', '2026-11-23', null),
  (20, 'Resultado preliminar das entrevistas, da heteroidentificação e classificação geral',                         null,         '2026-11-25', null),
  (21, 'Recurso contra resultado da entrevista, da heteroidentificação, das reservas de vagas e da classificação geral', '2026-11-26', '2026-11-30', '26, 27 e 30/11/2026'),
  (22, 'Julgamento dos recursos',                                                                                    '2026-12-01', '2026-12-03', '01, 02 e 03/12/2026'),
  (23, 'Resultado final do Processo Seletivo',                                                                       null,         '2026-12-04', null),
  (24, 'Homologação do resultado final',                                                                             null,         '2026-12-04', null);

-- Motor de regras: título/curso só pontua se concluído até a PUBLICAÇÃO do edital (Anexo I) — agora 28/09/2026.
-- Reescreve a função existente trocando só a data de corte, os textos e a versão (evita repetir o corpo inteiro).
do $$
declare d text;
begin
  d := pg_get_functiondef('interno.calcular_avaliacao(uuid)'::regprocedure);
  d := replace(d, '2026-09-24', '2026-09-28');
  d := replace(d, '(24/09/2026)', '(28/09/2026)');
  d := replace(d, 'v3-2026-09-22', 'v4-2026-09-24');
  execute d;
end;
$$;
