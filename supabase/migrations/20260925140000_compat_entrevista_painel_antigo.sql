-- Compatibilidade com o painel publicado ANTES da migração 20260925130000: a tela antiga da entrevista percorre o campo
-- "fichas" de painel.entrevista_do_candidato() e quebrava ("This page couldn't load") nos candidatos convocados, porque
-- o campo deixou de existir. Devolve sempre uma lista VAZIA (fichas cegas: nenhuma nota individual sai do banco).
-- O painel novo ignora este campo; pode ser retirado depois que o site novo estiver publicado.
-- Reversão: supabase/rollback/20260925140000_compat_entrevista_painel_antigo.down.sql

do $$
declare d text; ancora text;
begin
  d := pg_get_functiondef('painel.entrevista_do_candidato(uuid)'::regprocedure);
  ancora := '''minimo_fichas'', 3,';
  if position(ancora in d) = 0 then raise exception 'entrevista_do_candidato: trecho não encontrado'; end if;
  d := replace(d, ancora, '''fichas'', ''[]''::jsonb,
    ' || ancora);
  execute d;
end;
$$;
