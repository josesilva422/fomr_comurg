-- Ficha do avaliador TRAVADA no envio: depois de enviada, a ficha não é mais alterada por "salvar". Para corrigir, o
-- avaliador remove a própria ficha informando o motivo (painel.remover_minha_ficha; fica na auditoria) e lança de novo.
-- Também expõe painel.meu_perfil(): nome, e-mail e CPF (mascarado) do usuário logado, para a ficha mostrar quem é o avaliador
-- (o nome vem do cadastro do usuário do painel, não é digitado).
-- Reversão: supabase/rollback/20260928130000_ficha_travada_e_meu_perfil.down.sql

create or replace function painel.meu_perfil()
returns table (nome text, email text, cpf_mascarado text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select u.nome, u.email, case when u.cpf is null then null else '***.***.***-' || right(u.cpf, 2) end
    from interno.usuarios_internos u
    where u.user_id = auth.uid() and u.ativo;
end;
$$;
revoke execute on function painel.meu_perfil() from public, anon;
grant execute on function painel.meu_perfil() to authenticated;

do $$
declare
  d text;
  ancora constant text := $t$  for i in 1..6 loop
$t$;
  novo constant text := $t$  if exists (select 1 from interno.fichas_entrevista x where x.inscricao_id = p_inscricao_id and x.avaliador_id = auth.uid()) then
    raise exception 'Sua ficha já foi enviada e está travada. Para corrigir, remova-a informando o motivo e lance novamente.' using errcode = 'P0001', hint = 'ficha_ja_enviada';
  end if;
$t$ || ancora;
begin
  d := pg_get_functiondef('painel.salvar_ficha_entrevista(uuid,jsonb,jsonb)'::regprocedure);
  if position(ancora in d) = 0 then raise exception 'salvar_ficha_entrevista: trecho não encontrado'; end if;
  if (length(d) - length(replace(d, ancora, ''))) / length(ancora) <> 1 then raise exception 'salvar_ficha_entrevista: trecho ambíguo'; end if;
  execute replace(d, ancora, novo);
end;
$$;
