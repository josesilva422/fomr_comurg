-- Reverte 20260929170000_minuta_v9_publicacao_05_10.sql: volta às datas do edital de 28/09/2026.
update interno.configuracao set valor = to_jsonb('2026-09-28T00:00:00-03:00'::text), updated_at = now() where chave = 'inscricoes_abertura';
update interno.configuracao set valor = to_jsonb('2026-10-13T23:59:59-03:00'::text), updated_at = now() where chave = 'inscricoes_encerramento';
update interno.configuracao set valor = to_jsonb('2026-10-06T23:59:59-03:00'::text), updated_at = now() where chave = 'isencao_pedidos_fim';
update interno.configuracao set valor = to_jsonb('2026-10-16T23:59:59-03:00'::text), updated_at = now() where chave = 'isencao_pagamento_fim';
-- O cronograma de 28/09 (24 itens) está em 20260924110000_edital_publicado_28_09.sql (delete + insert de lá).
do $$
declare d text;
begin
  d := pg_get_functiondef('interno.calcular_avaliacao(uuid)'::regprocedure);
  d := replace(d, '''2026-10-05''', '''2026-09-28''');
  d := replace(d, '(05/10/2026)', '(28/09/2026)');
  d := replace(d, '''v8-2026-09-29''', '''v7-2026-09-25''');
  execute d;
  d := pg_get_functiondef('publico.verificar_inscricao()'::regprocedure);
  execute replace(d, 'terminou em 14/10/2026', 'terminou em 06/10/2026');
end;
$$;
