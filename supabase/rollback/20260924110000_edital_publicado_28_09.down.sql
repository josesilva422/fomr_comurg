-- Volta as datas para a minuta de 22/09 (abertura 24/09, encerramento 07/10, cronograma de 18 itens) e a data de corte do motor.
update interno.configuracao set valor = to_jsonb('2026-09-24T00:00:00-03:00'::text) where chave = 'inscricoes_abertura';
update interno.configuracao set valor = to_jsonb('2026-10-07T23:59:59-03:00'::text) where chave = 'inscricoes_encerramento';
-- O cronograma de 18 itens está na migração 20260922170000_convocacao_e_cronograma.sql (delete + insert de lá).
do $$
declare d text;
begin
  d := pg_get_functiondef('interno.calcular_avaliacao(uuid)'::regprocedure);
  d := replace(d, '2026-09-28', '2026-09-24');
  d := replace(d, '(28/09/2026)', '(24/09/2026)');
  d := replace(d, 'v4-2026-09-24', 'v3-2026-09-22');
  execute d;
end;
$$;
