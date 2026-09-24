-- Edital publicado, item 5.1.2: "Os diplomas digitais deverão possuir mecanismo idôneo de validação de autenticidade ...,
-- admitidos código de validação, assinatura digital, QR Code ou outro mecanismo oficial de verificação."
-- A minuta de 22/09 exigia código/QR e mandava inabilitar sem ele. Agora o candidato NÃO precisa digitar código: some a
-- pendência bloqueante 'diploma_digital_sem_codigo' de publico.verificar_inscricao(). A conferência do mecanismo de
-- validação continua sendo da Comissão. (O campo codigo_diploma_digital permanece, opcional.)
-- Esta versão é a função COMPLETA (igual à da migração 20260922150000, sem o bloco do diploma digital).
-- Reversão: supabase/rollback/20260924120000_diploma_digital_sem_codigo_obrigatorio.down.sql

drop function if exists publico.verificar_inscricao();
create function publico.verificar_inscricao()
returns table (codigo text, mensagem text, etapa integer, bloqueia boolean)
language plpgsql stable security definer set search_path = ''
as $$
declare
  i   publico.inscricoes;
  c   publico.candidatos;
  enc date := (interno.encerramento() at time zone 'America/Sao_Paulo')::date;
  r   record;
begin
  select x.* into i from publico.inscricoes x where x.id = publico.minha_inscricao_id();
  if not found then
    return query select 'sem_inscricao'::text, 'Complete seu cadastro para iniciar a inscrição.'::text, 1, true;
    return;
  end if;
  select x.* into c from publico.candidatos x where x.id = i.candidato_id;

  if not publico.inscricoes_abertas() then
    return query select 'periodo_encerrado'::text, 'O período de inscrições não está aberto.'::text, 7, true;
  end if;

  -- 1 · dados pessoais e documentos pessoais
  if c.data_nascimento > (enc - interval '18 years')::date then
    return query select 'menor_de_18'::text, 'É preciso ter 18 anos completos até o encerramento das inscrições.'::text, 1, true;
  end if;
  if not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'identidade') then
    return query select 'identidade_ausente'::text, 'Anexe o documento de identidade.'::text, 1, true;
  end if;

  -- 2 · grupo e nível
  if i.grupo is null or i.nivel is null then
    return query select 'grupo_nivel_ausente'::text, 'Escolha o grupo e o nível.'::text, 2, true;
  end if;

  -- 3 · graduação
  if i.curso_graduacao is null or i.grau_graduacao is null or nullif(btrim(i.instituicao_graduacao), '') is null
     or i.data_colacao is null or i.formato_diploma is null then
    return query select 'graduacao_incompleta'::text, 'Preencha todos os dados da graduação.'::text, 3, true;
  end if;
  if i.grupo is not null and i.nivel is not null and i.curso_graduacao is not null
     and not exists (select 1 from publico.cursos_aceitos a
                     where a.grupo = i.grupo and a.nivel = i.nivel and a.curso = i.curso_graduacao) then
    return query select 'curso_nao_aceito'::text, 'O curso informado não consta entre os aceitos para o grupo e o nível escolhidos.'::text, 3, true;
  end if;
  if i.data_colacao is not null and i.data_colacao > enc then
    return query select 'colacao_posterior'::text, 'A colação de grau precisa ter ocorrido até o encerramento das inscrições.'::text, 3, true;
  end if;
  -- edital publicado, 5.1.2: diploma digital tem mecanismo de validação (código, assinatura digital, QR Code...); não se exige código do candidato
  if not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'diploma_graduacao') then
    return query select 'diploma_ausente'::text, 'Anexe o diploma de graduação (frente e verso).'::text, 3, true;
  end if;
  if i.diploma_provisorio
     and not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'historico_escolar') then
    return query select 'historico_ausente'::text, 'Certificado provisório exige o histórico escolar com registro de colação de grau.'::text, 3, true;
  end if;
  if i.diploma_exterior then
    if not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'revalidacao_diploma') then
      return query select 'revalidacao_ausente'::text, 'Diploma estrangeiro exige a revalidação.'::text, 3, true;
    end if;
    if not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'traducao_juramentada') then
      return query select 'traducao_ausente'::text, 'Documento em língua estrangeira exige tradução juramentada.'::text, 3, true;
    end if;
  end if;

  -- título/curso sem certificado: AVISO, não bloqueia mais o envio (decisão do responsável, 22/09/2026) —
  -- mas sem o comprovante o item não conta na pontuação da análise curricular (interno.calcular_avaliacao).
  for r in
    select t.denominacao from publico.titulos_declarados t
    where t.inscricao_id = i.id
      and not exists (select 1 from publico.documentos d where d.titulo_id = t.id and d.ativo)
  loop
    return query select 'titulo_sem_documento'::text,
      format('Sem o certificado ou diploma de "%s" anexado, esse título não vai contar na pontuação da análise curricular.', r.denominacao), 3, false;
  end loop;
  for r in
    select k.denominacao from publico.cursos_declarados k
    where k.inscricao_id = i.id
      and not exists (select 1 from publico.documentos d where d.curso_id = k.id and d.ativo)
  loop
    return query select 'curso_sem_certificado'::text,
      format('Sem o certificado de "%s" anexado, esse curso não vai contar na pontuação da análise curricular.', r.denominacao), 3, false;
  end loop;

  -- 4 · experiência (o documento por vínculo não é exigido para enviar nem para pontuar — a pontuação de
  -- experiência é por tempo total comprovado, não por item; ver interno.calcular_avaliacao)
  if not exists (select 1 from publico.vinculos_declarados v where v.inscricao_id = i.id) then
    return query select 'vinculo_ausente'::text, 'Cadastre ao menos um vínculo de experiência.'::text, 4, true;
  end if;
  if i.nivel = 'senior'
     and not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'declaracao_lideranca') then
    return query select 'lideranca_ausente'::text, 'Nível Sênior: anexe a declaração específica de liderança técnica.'::text, 4, true;
  end if;

  -- 5 · vagas reservadas e isenção
  if i.cota_pcd then
    if i.data_laudo is null
       or not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'laudo_pcd') then
      return query select 'laudo_ausente'::text, 'Informe a data e anexe o laudo médico.'::text, 5, true;
    elsif i.data_laudo < (enc - interval '12 months')::date or i.data_laudo > enc then
      return query select 'laudo_fora_do_prazo'::text, 'O laudo deve ter sido emitido em até 12 meses antes do encerramento das inscrições.'::text, 5, true;
    end if;
  end if;
  if i.cota_racial
     and not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'autodeclaracao_racial') then
    return query select 'autodeclaracao_ausente'::text, 'Anexe a autodeclaração racial assinada.'::text, 5, true;
  end if;
  if i.solicitou_isencao
     and (nullif(btrim(i.justificativa_isencao), '') is null
          or not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'requerimento_isencao')) then
    return query select 'isencao_incompleta'::text, 'O pedido de isenção exige fundamentação e o requerimento anexado.'::text, 5, true;
  end if;

  -- 6 · pagamento (sem comprovante a inscrição não é concluída, exceto com pedido de isenção em análise)
  if not i.solicitou_isencao
     and not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'comprovante_pix') then
    return query select 'comprovante_pix_ausente'::text, 'Anexe o comprovante do Pix.'::text, 6, true;
  end if;

  -- 7 · declarações
  if i.declaracoes_aceitas_em is null then
    return query select 'declaracoes_nao_aceitas'::text, 'Aceite todas as declarações para enviar.'::text, 7, true;
  end if;
end;
$$;

revoke execute on function publico.verificar_inscricao() from public, anon;
grant execute on function publico.verificar_inscricao() to authenticated;
