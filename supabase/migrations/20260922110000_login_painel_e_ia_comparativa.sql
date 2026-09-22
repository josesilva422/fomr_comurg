-- Fase 2 · Apoio ao login em 2 etapas do painel (e-mail+senha, depois código) e à IA comparativa.
-- Reversão: supabase/rollback/20260922110000_login_painel_e_ia_comparativa.down.sql

------------------------------------------------------------------------------
-- painel.eh_membro: checa a allowlist por user_id, SEM depender de auth.uid() (a etapa de senha
-- roda antes de existir sessão persistida). Não vaza e-mail: só devolve true/false para um UUID que
-- o chamador já precisa ter obtido por login de senha válido.
------------------------------------------------------------------------------
create or replace function painel.eh_membro(p_user_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$ select interno.eh_usuario_interno(p_user_id) $$;
revoke execute on function painel.eh_membro(uuid) from public;
grant execute on function painel.eh_membro(uuid) to anon, authenticated;

------------------------------------------------------------------------------
-- Resumo do candidato para o cabeçalho da tela de detalhe do painel
------------------------------------------------------------------------------
create or replace function painel.candidato_resumo(p_inscricao_id uuid)
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

------------------------------------------------------------------------------
-- painel.dados_declarados_documento: o que o candidato informou, para a IA comparar com o que o
-- documento realmente diz. NÃO decide nada — só monta a lista de campos a conferir.
------------------------------------------------------------------------------
create or replace function painel.dados_declarados_documento(p_documento_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  d publico.documentos;
  i publico.inscricoes;
  c publico.candidatos;
  campos jsonb := '[]'::jsonb;
  t publico.titulos_declarados;
  k publico.cursos_declarados;
  v publico.vinculos_declarados;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;

  select * into d from publico.documentos where id = p_documento_id;
  if not found then raise exception 'Documento não encontrado.' using errcode = 'P0001'; end if;
  select * into i from publico.inscricoes where id = d.inscricao_id;
  select * into c from publico.candidatos where id = i.candidato_id;

  campos := campos || jsonb_build_object('campo', 'Nome completo do candidato', 'valor', c.nome);

  if d.tipo in ('identidade', 'cpf') then
    campos := campos || jsonb_build_object('campo', 'CPF', 'valor', c.cpf);

  elsif d.tipo in ('diploma_graduacao', 'historico_escolar', 'revalidacao_diploma') then
    campos := campos
      || jsonb_build_object('campo', 'Curso de graduação', 'valor', i.curso_graduacao)
      || jsonb_build_object('campo', 'Grau', 'valor', i.grau_graduacao::text)
      || jsonb_build_object('campo', 'Instituição de ensino', 'valor', i.instituicao_graduacao)
      || jsonb_build_object('campo', 'Data de colação de grau', 'valor', to_char(i.data_colacao, 'DD/MM/YYYY'));

  elsif d.tipo in ('diploma_pos', 'diploma_mestrado', 'diploma_doutorado') and d.titulo_id is not null then
    select * into t from publico.titulos_declarados where id = d.titulo_id;
    campos := campos
      || jsonb_build_object('campo', 'Tipo de título', 'valor', t.tipo::text)
      || jsonb_build_object('campo', 'Denominação do curso', 'valor', t.denominacao)
      || jsonb_build_object('campo', 'Instituição', 'valor', t.instituicao)
      || jsonb_build_object('campo', 'Carga horária', 'valor', t.carga_horaria || ' horas')
      || jsonb_build_object('campo', 'Data de conclusão', 'valor', to_char(t.data_conclusao, 'DD/MM/YYYY'));

  elsif d.tipo in ('certificado_curso', 'certificacao_profissional') and d.curso_id is not null then
    select * into k from publico.cursos_declarados where id = d.curso_id;
    campos := campos
      || jsonb_build_object('campo', 'Denominação do curso/certificação', 'valor', k.denominacao)
      || jsonb_build_object('campo', 'Instituição/entidade certificadora', 'valor', k.instituicao)
      || jsonb_build_object('campo', 'Data de conclusão/emissão', 'valor', to_char(k.data_conclusao, 'DD/MM/YYYY'));
    if k.carga_horaria is not null then
      campos := campos || jsonb_build_object('campo', 'Carga horária', 'valor', k.carga_horaria || ' horas');
    end if;
    if k.numero_credencial is not null then
      campos := campos
        || jsonb_build_object('campo', 'Número da credencial', 'valor', k.numero_credencial)
        || jsonb_build_object('campo', 'Código de verificação', 'valor', k.codigo_verificacao);
    end if;

  elsif d.tipo in ('experiencia_ctps', 'experiencia_declaracao', 'experiencia_contrato', 'experiencia_publica',
                    'experiencia_autonomo', 'art_rrt_acervo', 'declaracao_lideranca') and d.vinculo_id is not null then
    select * into v from publico.vinculos_declarados where id = d.vinculo_id;
    campos := campos
      || jsonb_build_object('campo', 'Empregador/contratante', 'valor', v.empregador_contratante)
      || jsonb_build_object('campo', 'Cargo/função', 'valor', v.cargo)
      || jsonb_build_object('campo', 'Início do vínculo', 'valor', to_char(v.inicio, 'MM/YYYY'))
      || jsonb_build_object('campo', 'Fim do vínculo', 'valor', case when v.ativo then 'vínculo ativo (sem data de fim)' else to_char(v.fim, 'MM/YYYY') end)
      || jsonb_build_object('campo', 'Atividades descritas pelo candidato', 'valor', v.descricao);
    if d.tipo = 'declaracao_lideranca' then
      campos := campos || jsonb_build_object('campo', 'Precisa descrever', 'valor', 'responsabilidades de liderança técnica ou coordenação (não pode ser declaração genérica)');
    end if;

  elsif d.tipo = 'laudo_pcd' then
    campos := campos || jsonb_build_object('campo', 'Data de emissão do laudo informada pelo candidato', 'valor', to_char(i.data_laudo, 'DD/MM/YYYY'));

  elsif d.tipo = 'comprovante_pix' then
    campos := campos || jsonb_build_object('campo', 'Valor esperado da taxa', 'valor', 'R$ 100,00');

  elsif d.tipo = 'requerimento_isencao' then
    campos := campos || jsonb_build_object('campo', 'Justificativa do pedido de isenção', 'valor', coalesce(i.justificativa_isencao, '(não informada)'));
  end if;

  return campos;
end;
$$;
revoke execute on function painel.dados_declarados_documento(uuid) from public, anon;
grant execute on function painel.dados_declarados_documento(uuid) to authenticated;
