-- Retira o campo de compatibilidade "fichas" (lista vazia) de painel.entrevista_do_candidato().
do $$
declare d text;
begin
  d := pg_get_functiondef('painel.entrevista_do_candidato(uuid)'::regprocedure);
  d := replace(d, '''fichas'', ''[]''::jsonb,
    ', '');
  execute d;
end;
$$;
