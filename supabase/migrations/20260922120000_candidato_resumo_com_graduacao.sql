-- Fase 2 · painel.candidato_resumo passa a trazer os dados da graduação (bacharelado), para o painel
-- mostrar isso como um tópico próprio (antes só aparecia grupo/nível, sem os detalhes do diploma).
-- Reversão: supabase/rollback/20260922120000_candidato_resumo_com_graduacao.down.sql
drop function if exists painel.candidato_resumo(uuid);
create function painel.candidato_resumo(p_inscricao_id uuid)
returns table (nome text, cpf text, email text, telefone text, grupo publico.grupo_vaga, nivel publico.nivel_vaga,
               status publico.status_inscricao, submetida_em timestamptz,
               curso_graduacao text, grau_graduacao publico.grau_graduacao, instituicao_graduacao text,
               data_colacao date, formato_diploma publico.formato_diploma, codigo_diploma_digital text,
               diploma_provisorio boolean, diploma_exterior boolean,
               cota_pcd boolean, cota_racial boolean, solicitou_isencao boolean)
language plpgsql security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select c.nome, c.cpf, c.email, c.telefone, i.grupo, i.nivel, i.status, i.submetida_em,
           i.curso_graduacao, i.grau_graduacao, i.instituicao_graduacao, i.data_colacao,
           i.formato_diploma, i.codigo_diploma_digital, i.diploma_provisorio, i.diploma_exterior,
           i.cota_pcd, i.cota_racial, i.solicitou_isencao
    from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id
    where i.id = p_inscricao_id;
end;
$$;
revoke execute on function painel.candidato_resumo(uuid) from public, anon;
grant execute on function painel.candidato_resumo(uuid) to authenticated;
