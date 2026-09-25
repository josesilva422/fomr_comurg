-- Fase 9 · Testes das correções do motor de regras conferidas com o edital publicado (25/09/2026 —
-- migração 20260925100000_motor_teto_cursos_e_pos_requisito_pleno.sql):
--   (1) teto de 15,0 de cursos/certificações aplicado sobre a soma, sem depender da ordem (Anexo I, item 2);
--   (2) pós-graduação que é o ÚNICO meio de cumprir o requisito do Pleno não pontua (Anexo I, item 1; 6.4.3);
--   (6) avisos metodológicos citam o edital nas faixas de experiência (Anexo I, item 3; 6.4.2).
-- e da migração 20260925110000_comprovante_experiencia_obrigatorio.sql:
--   (7) cada vínculo precisa do comprovante do item 5.3 — sem ele não conta na experiência e bloqueia o envio;
-- e da migração 20260925120000_comprovante_pos_requisito.sql:
--   (8) pós exigida (Sênior; Pleno sem equivalência) só vale com certificado anexado; equivalência do Pleno idem.
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
-- Uso local:  psql "$DATABASE_URL" -f supabase/tests/fase9_motor_edital.test.sql
-- Uso remoto: colar no SQL Editor do Supabase (ou via MCP execute_sql).
do $teste$
declare
  t text[] := '{}';
  v_total integer; nf integer;
  ins uuid;
  av interno.avaliacoes_curriculares;
begin
  execute $f$create function pg_temp.igual(p_atual text, p_esperado text, p_rotulo text) returns text language plpgsql as $b$
    begin
      if p_atual is not distinct from p_esperado then return null; end if;
      return p_rotulo || ' -> esperado [' || coalesce(p_esperado, 'NULL') || '] obtido [' || coalesce(p_atual, 'NULL') || ']';
    end $b$
  $f$;
  -- Anexa um documento (ativo) a um vínculo.
  execute $f$create function pg_temp.doc_vinculo(p_vinc uuid, p_tipo text) returns uuid language plpgsql as $b$
    declare v_insc uuid; v uuid;
    begin
      select inscricao_id into v_insc from publico.vinculos_declarados where id = p_vinc;
      insert into publico.documentos (inscricao_id, tipo, vinculo_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
        values (v_insc, p_tipo::publico.tipo_documento, p_vinc, v_insc || '/' || p_tipo || '/' || gen_random_uuid() || '.pdf', 'exp.pdf',
                md5(p_vinc::text) || md5(p_tipo || random()::text), 'application/pdf', 1000)
        returning id into v;
      return v;
    end $b$
  $f$;
  -- Candidato (como administrador) com um vínculo de p_inicio a p_fim, comprovado por CTPS; devolve o id da inscrição.
  execute $f$create function pg_temp.cand(p_n int, p_cpf text, p_grupo text, p_nivel text, p_curso text, p_inicio date, p_fim date)
    returns uuid language plpgsql as $b$
    declare v_uid uuid := ('f9000000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid; v_insc uuid; v_vinc uuid;
    begin
      insert into auth.users (id, aud, role, email) values (v_uid, 'authenticated', 'authenticated', 'm' || p_n || '@teste.local');
      insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade)
        values (v_uid, 'Motor Teste ' || p_n, p_cpf, '62999990000', '1985-05-05', 'brasileiro_nato');
      select id into v_insc from publico.inscricoes where candidato_id = (select id from publico.candidatos where user_id = v_uid);
      update publico.inscricoes set grupo = p_grupo::publico.grupo_vaga, nivel = p_nivel::publico.nivel_vaga, curso_graduacao = p_curso,
             grau_graduacao = 'bacharelado', instituicao_graduacao = 'UFG', data_colacao = '2005-12-15', formato_diploma = 'fisico'
        where id = v_insc;
      insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao)
        values (v_insc, 'privado', 'Empresa Teste', 'Analista', p_inicio, p_fim, false, 'Atividades de teste do vínculo')
        returning id into v_vinc;
      perform pg_temp.doc_vinculo(v_vinc, 'experiencia_ctps');
      return v_insc;
    end $b$
  $f$;
  -- Especialização com documento anexado.
  execute $f$create function pg_temp.pos(p_insc uuid, p_horas int, p_nome text) returns void language plpgsql as $b$
    declare v uuid;
    begin
      insert into publico.titulos_declarados (inscricao_id, tipo, denominacao, instituicao, carga_horaria, data_conclusao)
        values (p_insc, 'especializacao', p_nome, 'FGV', p_horas, '2018-06-01') returning id into v;
      insert into publico.documentos (inscricao_id, tipo, titulo_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
        values (p_insc, 'diploma_pos', v, p_insc || '/diploma_pos/' || gen_random_uuid() || '.pdf', 'pos.pdf',
                md5(v::text) || md5(p_nome), 'application/pdf', 1000);
    end $b$
  $f$;
  -- Curso (p_horas) ou certificação (p_horas null) com documento anexado.
  execute $f$create function pg_temp.curso(p_insc uuid, p_nome text, p_horas int, p_data date) returns void language plpgsql as $b$
    declare v uuid;
    begin
      if p_horas is null then
        insert into publico.cursos_declarados (inscricao_id, tipo, denominacao, instituicao, data_conclusao, numero_credencial, codigo_verificacao)
          values (p_insc, 'certificacao', p_nome, 'PMI', p_data, '123456', 'ABC-123') returning id into v;
      else
        insert into publico.cursos_declarados (inscricao_id, tipo, denominacao, instituicao, carga_horaria, data_conclusao)
          values (p_insc, 'curso', p_nome, 'ENAP', p_horas, p_data) returning id into v;
      end if;
      insert into publico.documentos (inscricao_id, tipo, curso_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
        values (p_insc, case when p_horas is null then 'certificacao_profissional' else 'certificado_curso' end::publico.tipo_documento, v,
                p_insc || '/cursos/' || gen_random_uuid() || '.pdf', 'curso.pdf', md5(v::text) || md5(p_nome), 'application/pdf', 1000);
    end $b$
  $f$;

  ---------------------------------------------------------------- (1) teto de 15,0 sobre a soma (Anexo I, item 2)
  -- 4 cursos ≥ 80h (3,0 cada, limite da faixa 9,0 → o 4º não pontua) + 1 curso de 40h (2,0) + 1 certificação (5,0)
  -- = 16,0 → 15,0 pelo teto. A certificação é a MAIS RECENTE: antes da correção ela recebia 0 e o total ficava em 11,0.
  ins := pg_temp.cand(1, '11122233043', 'A', 'junior', 'Administração', '2020-01-01', '2021-12-01');
  perform pg_temp.curso(ins, 'Revit ' || n, 80, '2019-01-01') from generate_series(1, 4) n;
  perform pg_temp.curso(ins, 'Excel Avançado', 40, '2019-02-01');
  perform pg_temp.curso(ins, 'Certificação PMP', null, '2021-01-01');
  av := interno.calcular_avaliacao(ins);
  t := t || pg_temp.igual(av.pontos_cursos::text, '15.00', 'cursos 9 + 2 + certificação 5 = 16 → teto 15,0 (certificação mais recente não é mais zerada)');
  t := t || pg_temp.igual(av.detalhamento #>> '{cursos,soma_itens}', '16.00', 'detalhamento guarda a soma bruta dos itens (16,0)');
  t := t || pg_temp.igual((select (x ->> 'pontos') from jsonb_array_elements(av.detalhamento #> '{cursos,itens}') x where x ->> 'tipo' = 'certificacao'),
                          '5.00', 'a certificação pontua 5,0 no item; o teto é aplicado no total');

  -- Mesmos itens, certificação a MAIS ANTIGA: mesmo resultado (não depende da ordem).
  ins := pg_temp.cand(2, '11122233124', 'A', 'junior', 'Administração', '2020-01-01', '2021-12-01');
  perform pg_temp.curso(ins, 'Certificação PMP', null, '2015-01-01');
  perform pg_temp.curso(ins, 'Revit ' || n, 80, '2019-01-01') from generate_series(1, 4) n;
  perform pg_temp.curso(ins, 'Excel Avançado', 40, '2019-02-01');
  av := interno.calcular_avaliacao(ins);
  t := t || pg_temp.igual(av.pontos_cursos::text, '15.00', 'mesma soma com a certificação em primeiro: 15,0 (independe da ordem)');

  -- Abaixo do teto nada muda: 2 cursos de 20h (1,0 cada) + 1 de 80h (3,0) = 5,0.
  ins := pg_temp.cand(3, '11122233205', 'A', 'junior', 'Administração', '2020-01-01', '2021-12-01');
  perform pg_temp.curso(ins, 'SEI Básico', 20, '2019-01-01');
  perform pg_temp.curso(ins, 'SEI Avançado', 39, '2019-01-02');
  perform pg_temp.curso(ins, 'AutoCAD Avançado', 80, '2019-01-03');
  av := interno.calcular_avaliacao(ins);
  t := t || pg_temp.igual(av.pontos_cursos::text, '5.00', 'soma abaixo do teto continua igual (1 + 1 + 3 = 5,0)');

  ---------------------------------------------------------------- (2) pós como requisito no Pleno (Anexo I, item 1; 6.4.3)
  -- A Pleno com 4 anos (48 meses) e 1 especialização: a pós é o ÚNICO meio de cumprir o requisito → habilita, não pontua.
  ins := pg_temp.cand(4, '11122233396', 'A', 'pleno', 'Engenharia Civil', '2020-01-01', '2023-12-01');
  perform pg_temp.pos(ins, 400, 'Gestão de Obras');
  av := interno.calcular_avaliacao(ins);
  t := t || pg_temp.igual(av.habilitado::text, 'true', 'A Pleno, 48 meses + pós: habilitado');
  t := t || pg_temp.igual(av.pontos_formacao::text, '0.00', 'A Pleno sem equivalência: a pós usada como requisito não pontua');
  t := t || pg_temp.igual((select (x ->> 'motivo_rejeicao' like '%requisito de pós-graduação do nível Pleno%')::text
                           from jsonb_array_elements(av.detalhamento #> '{formacao,itens}') x),
                          'true', 'o detalhamento explica que o título foi usado como requisito do Pleno');

  -- Duas especializações: uma cumpre o requisito, a outra pontua (2,0).
  perform pg_temp.pos(ins, 400, 'Engenharia de Custos');
  av := interno.calcular_avaliacao(ins);
  t := t || pg_temp.igual(av.pontos_formacao::text, '2.00', 'A Pleno com 2 pós: uma cumpre o requisito, a outra pontua 2,0');

  -- O título escolhido como requisito é o que atende 5.2.1 (≥ 360h), não o de 300h cadastrado antes.
  ins := pg_temp.cand(5, '11122233477', 'C', 'pleno', 'Direito', '2020-01-01', '2023-12-01');
  perform pg_temp.pos(ins, 300, 'Curso curto');
  perform pg_temp.pos(ins, 400, 'Direito Administrativo');
  av := interno.calcular_avaliacao(ins);
  t := t || pg_temp.igual((select x ->> 'denominacao' from jsonb_array_elements(av.detalhamento #> '{formacao,itens}') x
                           where x ->> 'motivo_rejeicao' like '%requisito%'),
                          'Direito Administrativo', 'o requisito usa a pós de 400h (atende 5.2.1), não a de 300h');

  -- Com equivalência por 5 anos (60 meses), a pós continua pontuando (decisão pendente nº 4).
  ins := pg_temp.cand(6, '11122233558', 'A', 'pleno', 'Engenharia Civil', '2019-01-01', '2023-12-01');
  perform pg_temp.pos(ins, 400, 'Gestão de Obras');
  av := interno.calcular_avaliacao(ins);
  t := t || pg_temp.igual(av.pontos_formacao::text, '2.00', 'A Pleno com 60 meses (equivalência) + pós: a pós pontua 2,0');

  -- Grupo B com certificação PMP ativa (equivalência) + pós: a pós pontua.
  ins := pg_temp.cand(7, '11122233639', 'B', 'pleno', 'Administração', '2020-01-01', '2023-12-01');
  perform pg_temp.pos(ins, 400, 'Gestão de Projetos');
  perform pg_temp.curso(ins, 'Certificação PMP', null, '2021-01-01');
  av := interno.calcular_avaliacao(ins);
  t := t || pg_temp.igual(av.pontos_formacao::text, '2.00', 'B Pleno com PMP ativa (equivalência) + pós: a pós pontua 2,0');

  -- Sem pós e sem equivalência: inabilitado.
  ins := pg_temp.cand(8, '11122233710', 'A', 'pleno', 'Engenharia Civil', '2020-01-01', '2023-12-01');
  av := interno.calcular_avaliacao(ins);
  t := t || pg_temp.igual(av.habilitado::text, 'false', 'A Pleno sem pós e sem 5 anos: inabilitado');
  t := t || pg_temp.igual((av.motivos @> '[{"codigo": "pos_ou_equivalencia_ausente"}]')::text, 'true', 'motivo pos_ou_equivalencia_ausente');

  ---------------------------------------------------------------- (6) avisos e versão
  t := t || pg_temp.igual(((av.detalhamento -> 'avisos_metodologicos')::text like '%convenção assumida; ver decisão pendente nº 1%')::text, 'false',
                          'aviso das faixas de experiência não diz mais "convenção assumida"');
  t := t || pg_temp.igual(((av.detalhamento -> 'avisos_metodologicos')::text like '%Anexo I, item 3, e item 6.4.2%')::text, 'true',
                          'aviso das faixas de experiência cita o edital');
  t := t || pg_temp.igual(av.versao_motor, 'v7-2026-09-25', 'versão do motor');

  ---------------------------------------------------------------- (7) comprovante de experiência (5.3)
  declare
    v_insc uuid; v_priv uuid; v_pub uuid; v_aut uuid; v_doc uuid; pend text;
  begin
    -- Júnior com 3 vínculos sem sobreposição, cada um de 24 meses: privado (comprovado pela CTPS do helper),
    -- público e autônomo ainda sem comprovante.
    v_insc := pg_temp.cand(9, '11122233809', 'A', 'junior', 'Administração', '2014-01-01', '2015-12-01');
    select id into v_priv from publico.vinculos_declarados where inscricao_id = v_insc;
    insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao) values
      (v_insc, 'publico', 'Prefeitura Teste', 'Assessor', '2017-01-01', '2018-12-01', false, 'Atividades de teste no órgão')
      returning id into v_pub;
    insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao) values
      (v_insc, 'autonomo', 'Cliente Teste', 'Consultor', '2020-01-01', '2021-12-01', false, 'Atividades de teste como autônomo')
      returning id into v_aut;

    t := t || pg_temp.igual(interno.vinculo_comprovado(v_priv)::text, 'true', 'privado com CTPS: comprovado');
    t := t || pg_temp.igual(interno.vinculo_comprovado(v_pub)::text, 'false', 'público sem documento: não comprovado');
    av := interno.calcular_avaliacao(v_insc);
    t := t || pg_temp.igual(av.detalhamento #>> '{experiencia,meses_comprovados}', '24', 'só o vínculo comprovado conta (24 meses, não 72)');
    t := t || pg_temp.igual(av.detalhamento #>> '{experiencia,vinculos_sem_comprovante}', '2', 'detalhamento aponta 2 vínculos sem comprovante');

    -- art/RRT sozinho não comprova; certidão do órgão comprova o público.
    perform pg_temp.doc_vinculo(v_pub, 'art_rrt_acervo');
    t := t || pg_temp.igual(interno.vinculo_comprovado(v_pub)::text, 'false', 'público só com ART/RRT: não comprovado (5.3.5 complementa)');
    v_doc := pg_temp.doc_vinculo(v_pub, 'experiencia_publica');
    t := t || pg_temp.igual(interno.vinculo_comprovado(v_pub)::text, 'true', 'público com certidão do órgão: comprovado');

    -- autônomo: só a nota fiscal não basta; precisa também da declaração do contratante (5.3.3).
    perform pg_temp.doc_vinculo(v_aut, 'experiencia_autonomo');
    t := t || pg_temp.igual(interno.vinculo_comprovado(v_aut)::text, 'false', 'autônomo só com contrato/RPA/NF: não comprovado');
    perform pg_temp.doc_vinculo(v_aut, 'experiencia_declaracao');
    t := t || pg_temp.igual(interno.vinculo_comprovado(v_aut)::text, 'true', 'autônomo com NF + declaração do contratante: comprovado');
    av := interno.calcular_avaliacao(v_insc);
    t := t || pg_temp.igual(av.detalhamento #>> '{experiencia,meses_comprovados}', '72', 'com os três comprovados: 72 meses');

    -- documento removido (ativo = false) deixa de comprovar
    update publico.documentos set ativo = false where id = v_doc;
    t := t || pg_temp.igual(interno.vinculo_comprovado(v_pub)::text, 'false', 'certidão removida: volta a não comprovar');

    -- pendência bloqueante na inscrição do candidato
    update interno.configuracao set valor = to_jsonb((now() - interval '1 day')::text) where chave = 'inscricoes_abertura';
    update interno.configuracao set valor = to_jsonb((now() + interval '7 days')::text) where chave = 'inscricoes_encerramento';
    perform set_config('request.jwt.claims', json_build_object('sub', 'f9000000-0000-0000-0000-000000000009', 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select string_agg(mensagem, ' | ') into pend from publico.verificar_inscricao() where codigo = 'vinculo_sem_comprovante' and bloqueia;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    t := t || pg_temp.igual((pend like '%Prefeitura Teste%' and pend not like '%Empresa Teste%' and pend not like '%Cliente Teste%')::text, 'true',
                            'pendência bloqueante só para o vínculo sem comprovante: ' || coalesce(pend, 'nenhuma'));
  end;

  ---------------------------------------------------------------- (8) pós exigida só com certificado (migração 20260925120000)
  declare
    v_insc uuid; v_tit uuid; v_cert uuid; pend text;
  begin
    execute $f$create function pg_temp.pend(p_n int) returns text language plpgsql as $b$
      declare r text;
      begin
        perform set_config('request.jwt.claims', json_build_object('sub', ('f9000000-0000-0000-0000-' || lpad(p_n::text, 12, '0')), 'role', 'authenticated')::text, true);
        execute 'set local role authenticated';
        select string_agg(mensagem, ' | ') into r from publico.verificar_inscricao() where codigo = 'pos_sem_comprovante' and bloqueia;
        execute 'reset role';
        perform set_config('request.jwt.claims', '', true);
        return r;
      end $b$
    $f$;

    -- Sênior com 9 anos comprovados e pós SEM certificado: inabilitado e envio bloqueado.
    v_insc := pg_temp.cand(10, '22233344073', 'A', 'senior', 'Engenharia Civil', '2015-01-01', '2023-12-01');
    insert into publico.titulos_declarados (inscricao_id, tipo, denominacao, instituicao, carga_horaria, data_conclusao)
      values (v_insc, 'especializacao', 'Gestão de Obras', 'FGV', 400, '2018-06-01') returning id into v_tit;
    av := interno.calcular_avaliacao(v_insc);
    t := t || pg_temp.igual((av.motivos @> '[{"codigo": "pos_obrigatoria_ausente"}]')::text, 'true', 'Sênior com pós sem certificado: requisito não comprovado');
    t := t || pg_temp.igual((pg_temp.pend(10) like 'Nível Sênior%')::text, 'true', 'Sênior com pós sem certificado: pendência bloqueante no envio');
    insert into publico.documentos (inscricao_id, tipo, titulo_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
      values (v_insc, 'diploma_pos', v_tit, v_insc || '/diploma_pos/' || gen_random_uuid() || '.pdf', 'pos.pdf', md5(v_tit::text) || md5('x'), 'application/pdf', 1000);
    av := interno.calcular_avaliacao(v_insc);
    t := t || pg_temp.igual((av.motivos @> '[{"codigo": "pos_obrigatoria_ausente"}]')::text, 'false', 'Sênior com certificado anexado: requisito de pós atendido');
    t := t || pg_temp.igual(pg_temp.pend(10), null, 'Sênior com certificado anexado: sem pendência de pós');

    -- Pleno (48 meses) com pós sem certificado: inabilitado; com certificado: habilita e a pós não pontua.
    v_insc := pg_temp.cand(11, '22233344154', 'C', 'pleno', 'Direito', '2020-01-01', '2023-12-01');
    insert into publico.titulos_declarados (inscricao_id, tipo, denominacao, instituicao, carga_horaria, data_conclusao)
      values (v_insc, 'especializacao', 'Direito Administrativo', 'PUC', 400, '2018-06-01') returning id into v_tit;
    av := interno.calcular_avaliacao(v_insc);
    t := t || pg_temp.igual((av.motivos @> '[{"codigo": "pos_ou_equivalencia_ausente"}]')::text, 'true', 'Pleno com pós sem certificado e sem equivalência: requisito não comprovado');
    t := t || pg_temp.igual((pg_temp.pend(11) like 'Nível Pleno%5 anos de experiência comprovada.')::text, 'true', 'Pleno (Grupo C): pendência sem citar certificação');
    insert into publico.documentos (inscricao_id, tipo, titulo_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
      values (v_insc, 'diploma_pos', v_tit, v_insc || '/diploma_pos/' || gen_random_uuid() || '.pdf', 'pos.pdf', md5(v_tit::text) || md5('y'), 'application/pdf', 1000);
    av := interno.calcular_avaliacao(v_insc);
    t := t || pg_temp.igual(av.habilitado::text, 'true', 'Pleno com certificado da pós: habilitado');
    t := t || pg_temp.igual(av.pontos_formacao::text, '0.00', 'Pleno: pós usada como requisito continua sem pontuar');

    -- Pleno B com PMP SEM certificado anexado e sem pós: não vale como equivalência; com certificado, vale.
    v_insc := pg_temp.cand(12, '22233344235', 'B', 'pleno', 'Administração', '2020-01-01', '2023-12-01');
    insert into publico.cursos_declarados (inscricao_id, tipo, denominacao, instituicao, data_conclusao, numero_credencial, codigo_verificacao)
      values (v_insc, 'certificacao', 'PMP', 'PMI', '2021-01-01', '999', 'COD-999') returning id into v_cert;
    t := t || pg_temp.igual(interno.pleno_tem_equivalencia(v_insc)::text, 'false', 'PMP sem certificado anexado não é equivalência');
    t := t || pg_temp.igual((pg_temp.pend(12) like '%certificação PMP, PgMP, PRINCE2 ou IPMA ativa%')::text, 'true', 'Pleno (Grupo B): pendência cita a certificação');
    insert into publico.documentos (inscricao_id, tipo, curso_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
      values (v_insc, 'certificacao_profissional', v_cert, v_insc || '/cursos/' || gen_random_uuid() || '.pdf', 'pmp.pdf', md5(v_cert::text) || md5('z'), 'application/pdf', 1000);
    t := t || pg_temp.igual(interno.pleno_tem_equivalencia(v_insc)::text, 'true', 'PMP com certificado anexado: equivalência');
    t := t || pg_temp.igual(pg_temp.pend(12), null, 'Pleno B com PMP comprovada: sem pendência de pós');

    -- Pleno com 5 anos comprovados e nenhuma pós: sem pendência (equivalência).
    v_insc := pg_temp.cand(13, '22233344316', 'A', 'pleno', 'Engenharia Civil', '2018-01-01', '2023-12-01');
    t := t || pg_temp.igual(pg_temp.pend(13), null, 'Pleno com 72 meses comprovados: equivalência, sem pendência de pós');
    t := t || pg_temp.igual((interno.calcular_avaliacao(v_insc)).habilitado::text, 'true', 'Pleno com 72 meses comprovados e sem pós: habilitado');
  end;

  ---------------------------------------------------------------- resultado (a exceção desfaz TUDO)
  select count(*), count(x) into v_total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', v_total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
