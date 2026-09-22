drop function if exists painel.candidato_resumo(uuid);
create function painel.candidato_resumo(p_inscricao_id uuid)
returns table (nome text, cpf text, email text, telefone text, grupo publico.grupo_vaga, nivel publico.nivel_vaga,
               status publico.status_inscricao, submetida_em timestamptz)
language plpgsql security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select c.nome, c.cpf, c.email, c.telefone, i.grupo, i.nivel, i.status, i.submetida_em
    from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id
    where i.id = p_inscricao_id;
end;
$$;
revoke execute on function painel.candidato_resumo(uuid) from public, anon;
grant execute on function painel.candidato_resumo(uuid) to authenticated;
