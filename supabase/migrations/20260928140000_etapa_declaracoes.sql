-- Declarações viram uma ETAPA própria do assistente de inscrição (7 · Declarações), e a Revisão e envio passa a ser a 8.
-- A pendência "declaracoes_nao_aceitas" continua na etapa 7 (agora a etapa Declarações: o "Corrigir" leva até lá) e a
-- pendência "periodo_encerrado" (que não é de nenhuma etapa em particular) passa para a etapa 8, a da Revisão.
-- Troca de texto simples em publico.verificar_inscricao(); erro se o trecho não existir ou se for ambíguo.
-- Reversão: supabase/rollback/20260928140000_etapa_declaracoes.down.sql

do $$
declare
  d text;
  antigo constant text := $t$'O período de inscrições não está aberto.'::text, 7, true$t$;
  novo constant text := $t$'O período de inscrições não está aberto.'::text, 8, true$t$;
begin
  d := pg_get_functiondef('publico.verificar_inscricao()'::regprocedure);
  if position(antigo in d) = 0 then raise exception 'verificar_inscricao: trecho não encontrado'; end if;
  if (length(d) - length(replace(d, antigo, ''))) / length(antigo) <> 1 then raise exception 'verificar_inscricao: trecho ambíguo'; end if;
  execute replace(d, antigo, novo);
end;
$$;
