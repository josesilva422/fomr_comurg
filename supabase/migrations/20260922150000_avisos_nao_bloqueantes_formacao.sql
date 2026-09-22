-- Pedido do responsável em 22/09/2026: título/curso sem comprovante anexado não deve mais BLOQUEAR o envio
-- da inscrição (só o vínculo de experiência tinha ganhado esse tratamento na migração anterior) — mas precisa
-- continuar avisando o candidato, com uma mensagem que explique a consequência real: o item não pontua.
--
-- Isso exige duas mudanças:
-- 1) publico.verificar_inscricao() ganha uma coluna "bloqueia": true para tudo que já bloqueava, false para
--    "sem certificado de título/curso" (que vira só um aviso). publico.submeter_inscricao() passa a contar
--    só as pendências com bloqueia = true.
-- 2) interno.calcular_avaliacao() passa a EXIGIR documento ativo vinculado ao título/curso para pontuar —
--    sem isso o aviso mostrado ao candidato ("não vai contar na pontuação") seria falso.
-- Reversão: supabase/rollback/20260922150000_avisos_nao_bloqueantes_formacao.down.sql

------------------------------------------------------------------------------
-- Motor de regras: título/curso sem documento ativo anexado não pontua.
------------------------------------------------------------------------------
create or replace function interno.calcular_avaliacao(p_inscricao_id uuid)
returns interno.avaliacoes_curriculares
language plpgsql security definer set search_path = ''
as $$
declare
  i publico.inscricoes;
  minimo_meses int;
  meses int;
  excedente int;
  motivos jsonb := '[]'::jsonb;
  habilitado boolean := true;
  pontos_formacao numeric(5,2) := 0;
  pontos_cursos numeric(5,2) := 0;
  pontos_experiencia numeric(5,2) := 0;
  det_formacao jsonb := '[]'::jsonb;
  det_cursos jsonb := '[]'::jsonb;
  req_modo text;
  excluir_titulo_id uuid;
  atende_pos boolean;
  r record;
  n_esp int := 0;
  n_mestrado int := 0;
  n_doutorado int := 0;
  pub_edital constant date := '2026-09-24';
  faixa_20_39 numeric := 0;
  faixa_40_79 numeric := 0;
  faixa_80 numeric := 0;
  resultado interno.avaliacoes_curriculares;
  pts numeric(5,2);
  motivo text;
  no_catalogo boolean;
begin
  select * into i from publico.inscricoes where id = p_inscricao_id;
  if not found then
    raise exception 'Inscrição não encontrada.' using errcode = 'P0001';
  end if;
  if i.grupo is null or i.nivel is null then
    raise exception 'Inscrição sem grupo/nível definido.' using errcode = 'P0001';
  end if;

  -- item 5.1.6: tecnólogo não é aceito em nenhum grupo ou nível
  if i.grau_graduacao = 'tecnologico' then
    habilitado := false;
    motivos := motivos || jsonb_build_object('codigo', 'grau_tecnologico',
      'mensagem', 'Formação em nível tecnólogo não é aceita em nenhum grupo ou nível (item 5.1.6).');
  end if;

  -- itens 3.2 a 3.4: o curso precisa constar na lista aceita para o grupo e o nível
  if not exists (
    select 1 from publico.cursos_aceitos a
    where a.grupo = i.grupo and a.nivel = i.nivel and a.curso = i.curso_graduacao
  ) then
    habilitado := false;
    motivos := motivos || jsonb_build_object('codigo', 'curso_fora_da_lista',
      'mensagem', 'O curso de graduação não consta na lista aceita para o grupo e o nível (itens 3.2 a 3.4).');
  end if;

  -- item 3.1 / tabela de requisitos por nível: experiência mínima
  minimo_meses := case i.nivel when 'junior' then 12 when 'pleno' then 48 when 'senior' then 96 end;
  meses := interno.meses_experiencia_uniao(p_inscricao_id);
  if meses < minimo_meses then
    habilitado := false;
    motivos := motivos || jsonb_build_object('codigo', 'experiencia_insuficiente',
      'mensagem', format('Experiência comprovada (%s meses) abaixo do mínimo exigido para o nível (%s meses).', meses, minimo_meses));
  end if;
  excedente := greatest(meses - minimo_meses, 0);

  -- pós-graduação: Júnior não exige; Sênior exige (obrigatória); Pleno exige com equivalência
  -- (itens 3.2.2/3.2.3, 3.3.2/3.3.3, 3.4.2/3.4.3 — ver REQUISITOS em requisitos.ts, mesma fonte)
  req_modo := case when i.nivel = 'junior' then 'nao' when i.nivel = 'senior' then 'obrig' else 'equiv' end;

  if req_modo = 'obrig' then
    select t.id into excluir_titulo_id from publico.titulos_declarados t
      where t.inscricao_id = p_inscricao_id and t.tipo = 'especializacao'
      order by t.created_at limit 1;
    if excluir_titulo_id is null then
      habilitado := false;
      motivos := motivos || jsonb_build_object('codigo', 'pos_obrigatoria_ausente',
        'mensagem', 'Pós-graduação lato sensu obrigatória para o nível Sênior não foi declarada.');
    end if;
  elsif req_modo = 'equiv' then
    atende_pos := exists (select 1 from publico.titulos_declarados t where t.inscricao_id = p_inscricao_id and t.tipo = 'especializacao')
      or meses >= 60
      or (i.grupo = 'B' and exists (
            select 1 from publico.cursos_declarados k
            where k.inscricao_id = p_inscricao_id and k.tipo = 'certificacao'
              and (k.denominacao ilike '%PMP%' or k.denominacao ilike '%PgMP%' or k.denominacao ilike '%PRINCE2%' or k.denominacao ilike '%IPMA%')
              and k.numero_credencial is not null and k.codigo_verificacao is not null
          ));
    if not atende_pos then
      habilitado := false;
      motivos := motivos || jsonb_build_object('codigo', 'pos_ou_equivalencia_ausente',
        'mensagem', 'Pós-graduação ou equivalência exigida para o nível Pleno não foi atendida.');
    end if;
  end if;

  ----------------------------------------------------------------------------
  -- Anexo I, item 1 · Formação Acadêmica Adicional (máx. 10,0)
  ----------------------------------------------------------------------------
  for r in select * from publico.titulos_declarados where inscricao_id = p_inscricao_id order by data_conclusao, created_at
  loop
    pts := 0; motivo := null;
    if r.id = excluir_titulo_id then
      motivo := 'Usado para cumprir o requisito obrigatório de pós-graduação do nível Sênior; não pontua (Anexo I, item 1).';
    elsif not exists (select 1 from publico.documentos d where d.titulo_id = r.id and d.ativo) then
      motivo := 'Sem certificado ou diploma anexado; não pontua.';
    elsif r.data_conclusao > pub_edital then
      motivo := 'Concluído depois da publicação do edital (24/09/2026); não pontua.';
    elsif r.tipo = 'especializacao' then
      if r.carga_horaria < 360 then
        motivo := 'Carga horária inferior a 360h; não pontua.';
      elsif n_esp >= 3 then
        motivo := 'Limite de 3 títulos de especialização/MBA já atingido (até 6,0 pontos).';
      else
        n_esp := n_esp + 1; pts := 2.0;
      end if;
    elsif r.tipo = 'mestrado' then
      if n_mestrado >= 1 then motivo := 'Limite de 1 título de mestrado já atingido.'; else n_mestrado := 1; pts := 3.0; end if;
    elsif r.tipo = 'doutorado' then
      if n_doutorado >= 1 then motivo := 'Limite de 1 título de doutorado já atingido.'; else n_doutorado := 1; pts := 4.0; end if;
    end if;
    pontos_formacao := pontos_formacao + pts;
    det_formacao := det_formacao || jsonb_build_object(
      'id', r.id, 'tipo', r.tipo, 'denominacao', r.denominacao, 'data_conclusao', r.data_conclusao,
      'pontos', pts, 'motivo_rejeicao', motivo,
      'observacao', case when pts > 0 then 'Correlação com as atribuições do Grupo exige confirmação da Comissão (Anexo I, item 1).' else null end
    );
  end loop;
  if pontos_formacao > 10 then pontos_formacao := 10; end if;

  ----------------------------------------------------------------------------
  -- Anexo I, item 2 · Cursos e Certificações Específicas (máx. 15,0; teto global rígido)
  ----------------------------------------------------------------------------
  for r in select * from publico.cursos_declarados where inscricao_id = p_inscricao_id order by data_conclusao, created_at
  loop
    pts := 0; motivo := null;
    no_catalogo := i.grupo is not null and exists (
      select 1 from interno.cursos_pontuaveis cp where cp.grupo = i.grupo and lower(r.denominacao) like '%' || lower(cp.denominacao) || '%'
    );
    if not exists (select 1 from publico.documentos d where d.curso_id = r.id and d.ativo) then
      motivo := 'Sem certificado anexado; não pontua.';
    elsif r.data_conclusao > pub_edital then
      motivo := 'Concluído depois da publicação do edital (24/09/2026); não pontua.';
    elsif r.tipo = 'curso' then
      if r.carga_horaria < 20 then
        motivo := 'Carga horária inferior a 20h; não pontua.';
      elsif pontos_cursos >= 15 then
        motivo := 'Teto global de 15,0 pontos do critério já atingido.';
      elsif r.carga_horaria between 20 and 39 then
        if faixa_20_39 >= 5 then motivo := 'Limite da faixa de 20 a 39 horas já atingido (até 5,0 pontos).';
        else faixa_20_39 := faixa_20_39 + 1; pts := 1.0; end if;
      elsif r.carga_horaria between 40 and 79 then
        if faixa_40_79 >= 6 then motivo := 'Limite da faixa de 40 a 79 horas já atingido (até 6,0 pontos).';
        else faixa_40_79 := faixa_40_79 + 2; pts := 2.0; end if;
      else -- 80h ou mais
        if faixa_80 >= 9 then motivo := 'Limite da faixa de 80 horas ou mais já atingido (até 9,0 pontos).';
        else faixa_80 := faixa_80 + 3; pts := 3.0; end if;
      end if;
    elsif r.tipo = 'certificacao' then
      if pontos_cursos >= 15 then motivo := 'Teto global de 15,0 pontos do critério já atingido.'; else pts := 5.0; end if;
    end if;
    if pts > 0 and pontos_cursos + pts > 15 then pts := 0; motivo := 'Teto global de 15,0 pontos do critério já atingido.'; end if;
    pontos_cursos := pontos_cursos + pts;
    det_cursos := det_cursos || jsonb_build_object(
      'id', r.id, 'tipo', r.tipo, 'denominacao', r.denominacao, 'carga_horaria', r.carga_horaria,
      'data_conclusao', r.data_conclusao, 'pontos', pts, 'motivo_rejeicao', motivo, 'no_catalogo_do_grupo', no_catalogo,
      'observacao', case when pts > 0 and not no_catalogo then 'Fora do catálogo exemplificativo (Anexo I, item 2.1); pontua se a Comissão confirmar correlação com o Grupo.' else null end
    );
  end loop;

  ----------------------------------------------------------------------------
  -- Anexo I, item 3 · Experiência Profissional Específica (máx. 35,0, por degrau)
  ----------------------------------------------------------------------------
  if excedente = 0 then pontos_experiencia := 0;
  elsif excedente <= 12 then pontos_experiencia := 5.0;
  elsif excedente <= 36 then pontos_experiencia := 15.0;
  elsif excedente <= 60 then pontos_experiencia := 25.0;
  else pontos_experiencia := 35.0;
  end if;

  ----------------------------------------------------------------------------
  -- Grava o resultado (rascunho — aguarda revisão humana da Comissão)
  ----------------------------------------------------------------------------
  insert into interno.avaliacoes_curriculares
    (inscricao_id, habilitado, motivos, pontos_formacao, pontos_cursos, pontos_experiencia, total, detalhamento, versao_motor)
  values (
    p_inscricao_id, habilitado, motivos, pontos_formacao, pontos_cursos, pontos_experiencia,
    pontos_formacao + pontos_cursos + pontos_experiencia,
    jsonb_build_object(
      'formacao', jsonb_build_object('itens', det_formacao, 'total', pontos_formacao, 'teto', 10),
      'cursos', jsonb_build_object('itens', det_cursos, 'total', pontos_cursos, 'teto', 15),
      'experiencia', jsonb_build_object('minimo_meses', minimo_meses, 'meses_comprovados', meses, 'excedente_meses', excedente, 'pontos', pontos_experiencia, 'teto', 35),
      'avisos_metodologicos', jsonb_build_array(
        'Faixas de experiência tratadas como intervalos (0,12], (12,36], (36,60], (60,∞) meses — convenção assumida; ver decisão pendente nº 1.',
        'Equivalência de pós-graduação no nível Pleno (título OU 5 anos OU certificação ativa no Grupo B) — convenção assumida; ver decisão pendente nº 4.',
        'Correlação de títulos/cursos com as atribuições do Grupo não é verificada automaticamente; exige confirmação da Comissão.',
        'Autenticidade de diplomas/certificados (e-MEC, Diplomas Digitais do MEC, portais de certificadoras) não é verificada aqui; é etapa manual da Comissão.',
        'Título ou curso sem documento comprobatório anexado não pontua (decisão do responsável, 22/09/2026).'
      )
    ),
    'v2-2026-09-22'
  )
  on conflict (inscricao_id) do update set
    habilitado = excluded.habilitado, motivos = excluded.motivos,
    pontos_formacao = excluded.pontos_formacao, pontos_cursos = excluded.pontos_cursos,
    pontos_experiencia = excluded.pontos_experiencia, total = excluded.total,
    detalhamento = excluded.detalhamento, versao_motor = excluded.versao_motor, calculado_em = now()
  returning * into resultado;

  return resultado;
end;
$$;

------------------------------------------------------------------------------
-- Pendências: ganham a coluna "bloqueia". Título/curso sem documento vira aviso (não bloqueia mais).
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
  if i.formato_diploma = 'digital' and nullif(btrim(i.codigo_diploma_digital), '') is null then
    return query select 'diploma_digital_sem_codigo'::text, 'Informe o código de autenticação ou o QR Code do diploma digital.'::text, 3, true;
  end if;
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

------------------------------------------------------------------------------
-- Envio: só conta pendências com bloqueia = true (avisos como "título sem documento" não impedem mais).
------------------------------------------------------------------------------
create or replace function publico.submeter_inscricao()
returns publico.status_inscricao
language plpgsql security definer set search_path = ''
as $$
declare
  v_id    uuid := publico.minha_inscricao_editavel_id();
  v_pend  integer;
  v_novo  publico.status_inscricao;
begin
  if v_id is null then
    raise exception 'Inscrição indisponível para edição.' using errcode = 'P0001', hint = 'inscricao_indisponivel';
  end if;
  select count(*) filter (where bloqueia) into v_pend from publico.verificar_inscricao();
  if v_pend > 0 then
    raise exception 'A inscrição tem % pendência(s).', v_pend using errcode = 'P0001', hint = 'inscricao_com_pendencias';
  end if;
  select case when x.solicitou_isencao then 'aguardando_isencao' else 'submetida' end::publico.status_inscricao
    into v_novo from publico.inscricoes x where x.id = v_id;
  update publico.inscricoes
     set status = v_novo, submetida_em = coalesce(submetida_em, now())
   where id = v_id;
  return v_novo;
end;
$$;

revoke execute on function publico.verificar_inscricao(), publico.submeter_inscricao() from public, anon;
grant execute on function publico.verificar_inscricao(), publico.submeter_inscricao() to authenticated;
