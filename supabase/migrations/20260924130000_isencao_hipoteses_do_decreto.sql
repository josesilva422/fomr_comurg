-- Pedido de isenção conforme o edital publicado (itens 4.10 e 4.10.1) e o decreto municipal que ele cita:
--   hipóteses (art. 1º): I baixa renda com CadÚnico · II doador de sangue · III doador de medula óssea
--   documentos (art. 4º): I NIS + declaração formal · II comprovantes das doações · III comprovante da doação + inscrição no REDOME
--   art. 4º, §5º: dados incompletos ou incorretos => indeferido.
-- O candidato escolhe a hipótese num menu e anexa o(s) documento(s). O campo "justificativa" deixa de ser exigido
-- (a coluna permanece, opcional). Também aplica o prazo do Anexo IV, item 4: pedidos de isenção de 28/09 a 06/10/2026.
-- NÃO decide isenção: a análise e a decisão motivada são da Comissão (a tela ainda será construída).
-- Reversão: supabase/rollback/20260924130000_isencao_hipoteses_do_decreto.down.sql

create type publico.hipotese_isencao as enum ('cadunico', 'doador_sangue', 'doador_medula');

alter table publico.inscricoes
  add column hipotese_isencao publico.hipotese_isencao,
  add column nis_isencao text;

grant update (hipotese_isencao, nis_isencao) on publico.inscricoes to authenticated;

insert into interno.configuracao (chave, valor, descricao) values
  ('isencao_pedidos_fim', to_jsonb('2026-10-06T23:59:59-03:00'::text), 'Fim do prazo para pedir isenção da taxa (edital publicado, Anexo IV, item 4: 28/09 a 06/10/2026).')
on conflict (chave) do nothing;

------------------------------------------------------------------------------
-- Pendências: isenção incompleta = sem hipótese, ou baixa renda sem NIS, ou sem documento; pedido fora do prazo.
-- (Função completa; igual à da migração 20260924120000, só o bloco da isenção mudou.)
------------------------------------------------------------------------------
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
  -- isenção (edital 4.10 e 4.10.1; decreto: art. 4º): hipótese escolhida + NIS (baixa renda) + documento(s) comprobatório(s)
  if i.solicitou_isencao
     and (i.hipotese_isencao is null
          or (i.hipotese_isencao = 'cadunico' and nullif(btrim(coalesce(i.nis_isencao, '')), '') is null)
          or not exists (select 1 from publico.documentos d where d.inscricao_id = i.id and d.ativo and d.tipo = 'requerimento_isencao')) then
    return query select 'isencao_incompleta'::text,
      'O pedido de isenção exige escolher a hipótese, informar o NIS (baixa renda) e anexar os documentos comprobatórios.'::text, 5, true;
  end if;
  -- Anexo IV, item 4: pedidos de isenção só até o fim do prazo (isencao_pedidos_fim)
  if i.solicitou_isencao
     and now() > (select (c2.valor #>> '{}')::timestamptz from interno.configuracao c2 where c2.chave = 'isencao_pedidos_fim') then
    return query select 'isencao_fora_do_prazo'::text,
      'O prazo para pedir isenção terminou em 06/10/2026 (Anexo IV, item 4). Desmarque o pedido e pague a taxa por Pix.'::text, 5, true;
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

------------------------------------------------------------------------------
-- Painel: o formulário/relatório passam a trazer hipótese e NIS; a IA compara o documento com a hipótese declarada.
-- (troca de texto simples nas funções existentes; erro se o trecho não for encontrado)
------------------------------------------------------------------------------
do $$
declare d text;
begin
  d := pg_get_functiondef('interno.registro_formulario(uuid)'::regprocedure);
  if position('''solicitou_isencao'', i.solicitou_isencao,' in d) = 0 then raise exception 'registro_formulario: trecho não encontrado'; end if;
  d := replace(d, '''solicitou_isencao'', i.solicitou_isencao,',
                  '''solicitou_isencao'', i.solicitou_isencao, ''hipotese_isencao'', i.hipotese_isencao, ''nis_isencao'', i.nis_isencao,');
  execute d;

  d := pg_get_functiondef('painel.dados_declarados_documento(uuid)'::regprocedure);
  if position('''Justificativa do pedido de isenção'', ''valor'', coalesce(i.justificativa_isencao, ''(não informada)'')' in d) = 0 then
    raise exception 'dados_declarados_documento: trecho não encontrado';
  end if;
  d := replace(d, '''Justificativa do pedido de isenção'', ''valor'', coalesce(i.justificativa_isencao, ''(não informada)'')',
                  '''Hipótese de isenção declarada (decreto municipal, art. 1º)'', ''valor'', coalesce(case i.hipotese_isencao when ''cadunico'' then ''Baixa renda (CadÚnico) — NIS '' || coalesce(i.nis_isencao, ''(não informado)'') when ''doador_sangue'' then ''Doador de sangue'' when ''doador_medula'' then ''Doador de medula óssea'' end, ''(não informada)'')');
  execute d;
end;
$$;
