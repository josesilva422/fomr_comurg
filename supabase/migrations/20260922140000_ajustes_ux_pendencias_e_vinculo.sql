-- Ajustes de UX pedidos pelo responsável em 22/09/2026:
-- 1) Documento comprovando cada vínculo de experiência deixa de ser obrigatório para enviar a inscrição
--    (continua podendo ser anexado, só não bloqueia mais o envio). O vínculo em si continua obrigatório
--    (precisa declarar ao menos um).
-- 2) As mensagens de pendência mostradas ao candidato não citam mais o número do item do edital — a citação
--    continua nos comentários do código e nas telas internas do painel da Comissão.
-- Reversão: supabase/rollback/20260922140000_ajustes_ux_pendencias_e_vinculo.down.sql

create or replace function publico.verificar_inscricao()
returns table (codigo text, mensagem text, etapa integer)
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
    return query select 'sem_inscricao'::text, 'Complete seu cadastro para iniciar a inscrição.'::text, 1;
    return;
  end if;
  select x.* into c from publico.candidatos x where x.id = i.candidato_id;

  if not publico.inscricoes_abertas() then
    return query select 'periodo_encerrado'::text, 'O período de inscrições não está aberto.'::text, 7;
  end if;

  -- 1 · dados pessoais e documentos pessoais
  if c.data_nascimento > (enc - interval '18 years')::date then
    return query select 'menor_de_18'::text, 'É preciso ter 18 anos completos até o encerramento das inscrições.'::text, 1;
  end if;
  if not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'identidade') then
    return query select 'identidade_ausente'::text, 'Anexe o documento de identidade.'::text, 1;
  end if;

  -- 2 · grupo e nível
  if i.grupo is null or i.nivel is null then
    return query select 'grupo_nivel_ausente'::text, 'Escolha o grupo e o nível.'::text, 2;
  end if;

  -- 3 · graduação
  if i.curso_graduacao is null or i.grau_graduacao is null or nullif(btrim(i.instituicao_graduacao), '') is null
     or i.data_colacao is null or i.formato_diploma is null then
    return query select 'graduacao_incompleta'::text, 'Preencha todos os dados da graduação.'::text, 3;
  end if;
  if i.grupo is not null and i.nivel is not null and i.curso_graduacao is not null
     and not exists (select 1 from publico.cursos_aceitos a
                     where a.grupo = i.grupo and a.nivel = i.nivel and a.curso = i.curso_graduacao) then
    return query select 'curso_nao_aceito'::text, 'O curso informado não consta entre os aceitos para o grupo e o nível escolhidos.'::text, 3;
  end if;
  if i.data_colacao is not null and i.data_colacao > enc then
    return query select 'colacao_posterior'::text, 'A colação de grau precisa ter ocorrido até o encerramento das inscrições.'::text, 3;
  end if;
  if i.formato_diploma = 'digital' and nullif(btrim(i.codigo_diploma_digital), '') is null then
    return query select 'diploma_digital_sem_codigo'::text, 'Informe o código de autenticação ou o QR Code do diploma digital.'::text, 3;
  end if;
  if not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'diploma_graduacao') then
    return query select 'diploma_ausente'::text, 'Anexe o diploma de graduação (frente e verso).'::text, 3;
  end if;
  if i.diploma_provisorio
     and not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'historico_escolar') then
    return query select 'historico_ausente'::text, 'Certificado provisório exige o histórico escolar com registro de colação de grau.'::text, 3;
  end if;
  if i.diploma_exterior then
    if not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'revalidacao_diploma') then
      return query select 'revalidacao_ausente'::text, 'Diploma estrangeiro exige a revalidação.'::text, 3;
    end if;
    if not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'traducao_juramentada') then
      return query select 'traducao_ausente'::text, 'Documento em língua estrangeira exige tradução juramentada.'::text, 3;
    end if;
  end if;

  for r in
    select t.denominacao from publico.titulos_declarados t
    where t.inscricao_id = i.id
      and not exists (select 1 from publico.documentos d where d.titulo_id = t.id and d.ativo)
  loop
    return query select 'titulo_sem_documento'::text, format('Anexe o certificado ou diploma de "%s".', r.denominacao), 3;
  end loop;
  for r in
    select k.denominacao from publico.cursos_declarados k
    where k.inscricao_id = i.id
      and not exists (select 1 from publico.documentos d where d.curso_id = k.id and d.ativo)
  loop
    return query select 'curso_sem_certificado'::text, format('Anexe o certificado de "%s".', r.denominacao), 3;
  end loop;

  -- 4 · experiência (o documento por vínculo deixou de ser exigido para enviar; ver comentário no topo)
  if not exists (select 1 from publico.vinculos_declarados v where v.inscricao_id = i.id) then
    return query select 'vinculo_ausente'::text, 'Cadastre ao menos um vínculo de experiência.'::text, 4;
  end if;
  if i.nivel = 'senior'
     and not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'declaracao_lideranca') then
    return query select 'lideranca_ausente'::text, 'Nível Sênior: anexe a declaração específica de liderança técnica.'::text, 4;
  end if;

  -- 5 · vagas reservadas e isenção
  if i.cota_pcd then
    if i.data_laudo is null
       or not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'laudo_pcd') then
      return query select 'laudo_ausente'::text, 'Informe a data e anexe o laudo médico.'::text, 5;
    elsif i.data_laudo < (enc - interval '12 months')::date or i.data_laudo > enc then
      return query select 'laudo_fora_do_prazo'::text, 'O laudo deve ter sido emitido em até 12 meses antes do encerramento das inscrições.'::text, 5;
    end if;
  end if;
  if i.cota_racial
     and not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'autodeclaracao_racial') then
    return query select 'autodeclaracao_ausente'::text, 'Anexe a autodeclaração racial assinada.'::text, 5;
  end if;
  if i.solicitou_isencao
     and (nullif(btrim(i.justificativa_isencao), '') is null
          or not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'requerimento_isencao')) then
    return query select 'isencao_incompleta'::text, 'O pedido de isenção exige fundamentação e o requerimento anexado.'::text, 5;
  end if;

  -- 6 · pagamento (sem comprovante a inscrição não é concluída, exceto com pedido de isenção em análise)
  if not i.solicitou_isencao
     and not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'comprovante_pix') then
    return query select 'comprovante_pix_ausente'::text, 'Anexe o comprovante do Pix.'::text, 6;
  end if;

  -- 7 · declarações
  if i.declaracoes_aceitas_em is null then
    return query select 'declaracoes_nao_aceitas'::text, 'Aceite todas as declarações para enviar.'::text, 7;
  end if;
end;
$$;
