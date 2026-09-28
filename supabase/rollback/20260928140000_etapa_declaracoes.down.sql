-- Volta a pendência "periodo_encerrado" para a etapa 7 (troca de texto simples).
do $$
declare
  d text;
  antigo constant text := $t$'O período de inscrições não está aberto.'::text, 8, true$t$;
  novo constant text := $t$'O período de inscrições não está aberto.'::text, 7, true$t$;
begin
  d := pg_get_functiondef('publico.verificar_inscricao()'::regprocedure);
  if position(antigo in d) = 0 then raise exception 'verificar_inscricao: trecho não encontrado'; end if;
  execute replace(d, antigo, novo);
end;
$$;
