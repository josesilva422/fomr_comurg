-- Tela "Usuários do painel": quem tem acesso, perfil, situação, último acesso liberado e quais candidatos cada um avaliou
-- na entrevista técnica (fichas lançadas por aquele login). Só leitura; cadastro de usuários continua pelo banco.
-- O CPF sai mascarado (só os 2 últimos dígitos); o número completo não trafega para a tela.
-- Reversão: supabase/rollback/20260924160000_listar_usuarios_painel.down.sql

create or replace function painel.listar_usuarios_painel()
returns table (
  user_id uuid, nome text, email text, perfil text, ativo boolean,
  cpf_mascarado text, senha_definida boolean, bloqueado_ate timestamptz,
  ultimo_acesso timestamptz, qtd_fichas integer, avaliados jsonb
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select u.user_id, u.nome, u.email, u.perfil, u.ativo,
           case when u.cpf is null then null else '***.***.***-' || right(u.cpf, 2) end,
           u.senha_hash is not null,
           case when u.bloqueado_ate > now() then u.bloqueado_ate end,
           (select max(s.criada_em) from interno.sessoes_painel s where s.user_id = u.user_id),
           (select count(*)::integer from interno.fichas_entrevista f where f.lancado_por = u.user_id),
           coalesce((
             select jsonb_agg(jsonb_build_object(
                      'inscricao_id', f.inscricao_id, 'candidato', c.nome, 'grupo', i.grupo, 'nivel', i.nivel,
                      'avaliador_informado', f.avaliador_nome, 'total', f.total, 'lancada_em', f.created_at)
                    order by f.created_at desc)
             from interno.fichas_entrevista f
             join publico.inscricoes i on i.id = f.inscricao_id
             join publico.candidatos c on c.id = i.candidato_id
             where f.lancado_por = u.user_id
           ), '[]'::jsonb)
    from interno.usuarios_internos u
    order by u.ativo desc, u.nome;
end;
$$;

revoke execute on function painel.listar_usuarios_painel() from public, anon;
grant execute on function painel.listar_usuarios_painel() to authenticated;
