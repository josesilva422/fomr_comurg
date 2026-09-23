-- Relatório de respostas do formulário (download em Excel e PDF no painel), a pedido do responsável em 23/09/2026,
-- para a Comissão confrontar o que o candidato respondeu. Só quem está em interno.usuarios_internos; exige ao
-- menos um filtro (Grupo, Nível ou nome/CPF) e só traz inscrições JÁ ENVIADAS (não rascunho). Cada geração
-- fica registrada em interno.auditoria (dados pessoais e sensíveis, CLAUDE.md seção 10).
-- Reversão: supabase/rollback/20260923100000_relatorio_respostas.down.sql

create or replace function painel.relatorio_respostas(
  p_grupo publico.grupo_vaga default null,
  p_nivel publico.nivel_vaga default null,
  p_busca text default null
)
returns setof jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_busca  text := nullif(btrim(coalesce(p_busca, '')), '');
  v_digitos text := regexp_replace(coalesce(p_busca, ''), '\D', '', 'g');
  v_total  integer;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if p_grupo is null and p_nivel is null and v_busca is null then
    raise exception 'Informe ao menos um filtro: grupo, nível ou nome/CPF.' using errcode = 'P0001', hint = 'filtro_obrigatorio';
  end if;

  select count(*) into v_total
  from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id
  where i.status <> 'rascunho'
    and (p_grupo is null or i.grupo = p_grupo)
    and (p_nivel is null or i.nivel = p_nivel)
    and (v_busca is null or c.nome ilike '%' || v_busca || '%' or (v_digitos <> '' and c.cpf like '%' || v_digitos || '%'));

  insert into interno.auditoria (ator_id, ator_role, acao, entidade, dados_depois)
  values (auth.uid(), 'authenticated', 'EXPORTAR_RELATORIO', 'painel.relatorio_respostas',
          jsonb_build_object('grupo', p_grupo, 'nivel', p_nivel, 'busca', v_busca, 'candidatos', v_total));

  return query
    select jsonb_build_object(
      'nome', c.nome, 'cpf', c.cpf, 'email', c.email, 'telefone', c.telefone,
      'data_nascimento', c.data_nascimento, 'nacionalidade', c.nacionalidade,
      'grupo', i.grupo, 'nivel', i.nivel, 'status', i.status, 'submetida_em', i.submetida_em,
      'curso_graduacao', i.curso_graduacao, 'grau_graduacao', i.grau_graduacao,
      'instituicao_graduacao', i.instituicao_graduacao, 'data_colacao', i.data_colacao,
      'formato_diploma', i.formato_diploma, 'codigo_diploma_digital', i.codigo_diploma_digital,
      'diploma_provisorio', i.diploma_provisorio, 'diploma_exterior', i.diploma_exterior,
      'cota_pcd', i.cota_pcd, 'data_laudo', i.data_laudo, 'cota_racial', i.cota_racial,
      'solicitou_isencao', i.solicitou_isencao, 'justificativa_isencao', i.justificativa_isencao,
      'declaracoes_aceitas_em', i.declaracoes_aceitas_em, 'declaracoes_versao', i.declaracoes_versao,
      'titulos', coalesce((
        select jsonb_agg(jsonb_build_object(
          'tipo', t.tipo, 'denominacao', t.denominacao, 'instituicao', t.instituicao,
          'carga_horaria', t.carga_horaria, 'data_conclusao', t.data_conclusao,
          'tem_documento', exists (select 1 from publico.documentos d where d.titulo_id = t.id and d.ativo)
        ) order by t.data_conclusao, t.created_at)
        from publico.titulos_declarados t where t.inscricao_id = i.id), '[]'::jsonb),
      'cursos', coalesce((
        select jsonb_agg(jsonb_build_object(
          'tipo', k.tipo, 'denominacao', k.denominacao, 'instituicao', k.instituicao,
          'carga_horaria', k.carga_horaria, 'data_conclusao', k.data_conclusao,
          'numero_credencial', k.numero_credencial, 'codigo_verificacao', k.codigo_verificacao,
          'tem_documento', exists (select 1 from publico.documentos d where d.curso_id = k.id and d.ativo)
        ) order by k.data_conclusao, k.created_at)
        from publico.cursos_declarados k where k.inscricao_id = i.id), '[]'::jsonb),
      'vinculos', coalesce((
        select jsonb_agg(jsonb_build_object(
          'tipo', v.tipo, 'empregador_contratante', v.empregador_contratante, 'cargo', v.cargo,
          'inicio', v.inicio, 'fim', v.fim, 'ativo', v.ativo, 'descricao', v.descricao
        ) order by v.inicio, v.created_at)
        from publico.vinculos_declarados v where v.inscricao_id = i.id), '[]'::jsonb),
      'documentos', coalesce((
        select jsonb_agg(jsonb_build_object(
          'tipo', d.tipo, 'nome_original', d.nome_original, 'enviado_em', d.enviado_em
        ) order by d.enviado_em)
        from publico.documentos d where d.inscricao_id = i.id and d.ativo), '[]'::jsonb)
    )
    from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id
    where i.status <> 'rascunho'
      and (p_grupo is null or i.grupo = p_grupo)
      and (p_nivel is null or i.nivel = p_nivel)
      and (v_busca is null or c.nome ilike '%' || v_busca || '%' or (v_digitos <> '' and c.cpf like '%' || v_digitos || '%'))
    order by c.nome;
end;
$$;

revoke execute on function painel.relatorio_respostas(publico.grupo_vaga, publico.nivel_vaga, text) from public, anon;
grant execute on function painel.relatorio_respostas(publico.grupo_vaga, publico.nivel_vaga, text) to authenticated;
