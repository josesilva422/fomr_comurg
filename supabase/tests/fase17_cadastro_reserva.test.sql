-- Fase 17 · Cadastro de reserva e publicação do resultado final (migração
-- 20261001240000_publicacao_resultado_final.sql): painel.classificacao_final ganhou o campo "vagas";
-- painel.publicar_resultado_final classifica cada convocado em classificado (vaga imediata), cadastro de
-- reserva (itens 2.1/11.1, minuta v11: 2 por vaga) ou eliminado na entrevista (6.5.7), e publica em
-- publico.resultados_candidato etapa 'resultado_final' (Anexo IV, item 23).
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
-- Uso remoto: colar no SQL Editor do Supabase (ou via MCP execute_sql).
do $teste$
declare
  ustaff constant uuid := 'f7000000-0000-0000-0000-00000000000f';
  ux constant uuid := 'f7000000-0000-0000-0000-000000000001';
  uy constant uuid := 'f7000000-0000-0000-0000-000000000002';
  uz constant uuid := 'f7000000-0000-0000-0000-000000000003';
  u_im1 constant uuid := 'f7000000-0000-0000-0000-000000000011';
  u_im2 constant uuid := 'f7000000-0000-0000-0000-000000000012';
  u_rs1 constant uuid := 'f7000000-0000-0000-0000-000000000013';
  u_rs2 constant uuid := 'f7000000-0000-0000-0000-000000000014';
  u_eli constant uuid := 'f7000000-0000-0000-0000-000000000015';
  u_inc constant uuid := 'f7000000-0000-0000-0000-000000000016';
  i_im1 uuid; i_im2 uuid; i_rs1 uuid; i_rs2 uuid; i_eli uuid; i_inc uuid;
  t text[] := '{}';
  p text; n integer; total integer; nf integer; qtd integer;
  j constant jsonb := '{"dominio":"adequado","analise":"adequado","planejamento":"adequado","comunicacao":"adequado","caso":"adequado","postura":"adequado"}';
begin
  execute $f$create function pg_temp.como(p_uid uuid, p_email text) returns void language plpgsql as $b$
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
      execute 'set local role authenticated';
    end $b$
  $f$;
  execute $f$create function pg_temp.admin() returns void language plpgsql as $b$
    begin
      execute 'reset role';
      perform set_config('request.jwt.claims', '', true);
    end $b$
  $f$;
  execute $f$create function pg_temp.igual(p_atual text, p_esperado text, p_rotulo text) returns text language plpgsql as $b$
    begin
      if p_atual is not distinct from p_esperado then return null; end if;
      return p_rotulo || ' -> esperado [' || coalesce(p_esperado, 'NULL') || '] obtido [' || coalesce(p_atual, 'NULL') || ']';
    end $b$
  $f$;
  execute $f$create function pg_temp.falha(p_sql text, p_rotulo text, p_trecho text default null) returns text language plpgsql as $b$
    declare v_msg text; v_hint text;
    begin
      execute p_sql;
      return p_rotulo || ' -> deveria falhar e passou';
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint;
      v_msg := sqlerrm;
      if p_trecho is not null and v_msg not ilike ('%' || p_trecho || '%') and coalesce(v_hint, '') not ilike ('%' || p_trecho || '%') then
        return p_rotulo || ' -> falhou com outro erro: ' || v_msg;
      end if;
      return null;
    end $b$
  $f$;
  -- Candidato habilitado para Grupo B Pleno (Administração; pós cumpre o requisito do Pleno), com um
  -- vínculo de 132 meses (bem acima dos 48 mínimos -> experiência no teto de 35,0). AC = pontos_formacao
  -- (2,0 por especialização, até 5) + 35,0 de experiência. Devolve a inscrição, já submetida.
  execute $f$create function pg_temp.cand(p_uid uuid, p_n int, p_cpf text, p_n_especializacoes int) returns uuid language plpgsql as $b$
    declare v_insc uuid; v_vinc uuid; v_tit uuid; i int;
    begin
      execute 'reset role';
      perform set_config('request.jwt.claims', '', true);
      insert into auth.users (id, aud, role, email) values (p_uid, 'authenticated', 'authenticated', 'cr' || p_n || '@teste.local');
      perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', 'cr' || p_n || '@teste.local')::text, true);
      execute 'set local role authenticated';
      insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade)
        values (p_uid, 'Reserva Teste ' || p_n, p_cpf, '62999990000', '1985-05-05', 'brasileiro_nato');
      select id into v_insc from publico.inscricoes where candidato_id = (select id from publico.candidatos where user_id = p_uid);
      update publico.inscricoes set grupo = 'B', nivel = 'pleno', curso_graduacao = 'Administração',
             grau_graduacao = 'bacharelado', instituicao_graduacao = 'UFG', data_colacao = '2005-12-15', formato_diploma = 'fisico'
        where id = v_insc;
      insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao)
        values (v_insc, 'privado', 'Empresa Teste', 'Analista', '2010-01-01'::date, '2021-12-01'::date, false, 'Atividades de teste do vínculo')
        returning id into v_vinc;
      insert into publico.documentos (inscricao_id, tipo, vinculo_id, storage_path, nome_original, sha256, mime, tamanho_bytes) values
        (v_insc, 'identidade', null, v_insc || '/identidade/' || gen_random_uuid() || '.pdf', 'rg.pdf', md5(v_insc::text) || md5('rg' || p_n), 'application/pdf', 1000),
        (v_insc, 'diploma_graduacao', null, v_insc || '/diploma_graduacao/' || gen_random_uuid() || '.pdf', 'diploma.pdf', md5(v_insc::text) || md5('dip' || p_n), 'application/pdf', 1000),
        (v_insc, 'experiencia_ctps', v_vinc, v_insc || '/experiencia_ctps/' || gen_random_uuid() || '.pdf', 'ctps.pdf', md5(v_vinc::text) || md5('exp' || p_n), 'application/pdf', 1000),
        (v_insc, 'comprovante_pix', null, v_insc || '/comprovante_pix/' || gen_random_uuid() || '.png', 'pix.png', md5(v_insc::text) || md5('pix' || p_n), 'image/png', 1000);
      for i in 1..p_n_especializacoes loop
        insert into publico.titulos_declarados (inscricao_id, tipo, denominacao, instituicao, carga_horaria, data_conclusao)
          values (v_insc, 'especializacao', 'Pós ' || i, 'FGV', 400, '2020-01-01') returning id into v_tit;
        insert into publico.documentos (inscricao_id, tipo, titulo_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
          values (v_insc, 'diploma_pos', v_tit, v_insc || '/diploma_pos/' || gen_random_uuid() || '.pdf', 'pos.pdf', md5(v_tit::text) || md5('pos' || i || p_n), 'application/pdf', 1000);
      end loop;
      perform publico.aceitar_declaracoes();
      perform publico.submeter_inscricao();
      return v_insc;
    end $b$
  $f$;

  update interno.configuracao set valor = to_jsonb((now() - interval '1 day')::text) where chave = 'inscricoes_abertura';
  update interno.configuracao set valor = to_jsonb((now() + interval '7 days')::text) where chave = 'inscricoes_encerramento';
  -- dentro desta transação (desfeita no fim) a exigência de sessão validada do painel é desligada, como em fase4_entrevista
  update interno.configuracao set valor = 'false'::jsonb where chave = 'painel_exige_login_seguro';

  insert into auth.users (id, aud, role, email) values
    (ustaff, 'authenticated', 'authenticated', 'staff-cr@teste.local'),
    (ux, 'authenticated', 'authenticated', 'x-cr@teste.local'), (uy, 'authenticated', 'authenticated', 'y-cr@teste.local'),
    (uz, 'authenticated', 'authenticated', 'z-cr@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email, perfil) values
    (ustaff, 'Comissão Reserva Teste', 'staff-cr@teste.local', 'comissao'),
    (ux, 'Avaliador CR X', 'x-cr@teste.local', 'comissao'), (uy, 'Avaliador CR Y', 'y-cr@teste.local', 'comissao'),
    (uz, 'Avaliador CR Z', 'z-cr@teste.local', 'comissao');

  -- Grupo B / Pleno: vagas = 2 -> corte de convocação (3x) = 6; cadastro de reserva = 2 por vaga = 4 (posições 3 a 6).
  i_im1 := pg_temp.cand(u_im1, 1, '11144477735', 5); -- AC 45
  i_im2 := pg_temp.cand(u_im2, 2, '52998224725', 3); -- AC 41
  i_rs1 := pg_temp.cand(u_rs1, 3, '39053344705', 1); -- AC 37
  i_rs2 := pg_temp.cand(u_rs2, 4, '22233344316', 1); -- AC 37
  i_eli := pg_temp.cand(u_eli, 5, '12345678909', 0); -- AC 35
  i_inc := pg_temp.cand(u_inc, 6, '98765432100', 0); -- AC 35 (banca incompleta)

  -- Fichas (3 avaliadores: banca completa). Notas: dominio(10) analise(10) planejamento(5) comunicacao(5) caso(5) postura(5).
  perform pg_temp.como(ux, 'x-cr@teste.local');
  perform painel.salvar_ficha_entrevista(i_im1, '{"dominio":10,"analise":10,"planejamento":4,"comunicacao":3,"caso":2,"postura":1}', j);
  perform painel.salvar_ficha_entrevista(i_im2, '{"dominio":10,"analise":10,"planejamento":4,"comunicacao":3,"caso":2,"postura":1}', j);
  perform painel.salvar_ficha_entrevista(i_rs1, '{"dominio":9,"analise":8,"planejamento":3,"comunicacao":2,"caso":2,"postura":1}', j);
  perform painel.salvar_ficha_entrevista(i_rs2, '{"dominio":8,"analise":7,"planejamento":2,"comunicacao":2,"caso":1,"postura":0}', j);
  perform painel.salvar_ficha_entrevista(i_eli, '{"dominio":4,"analise":3,"planejamento":1,"comunicacao":1,"caso":1,"postura":0}', j);
  perform painel.salvar_ficha_entrevista(i_inc, '{"dominio":10,"analise":10,"planejamento":4,"comunicacao":3,"caso":2,"postura":1}', j);
  perform pg_temp.como(uy, 'y-cr@teste.local');
  perform painel.salvar_ficha_entrevista(i_im1, '{"dominio":10,"analise":10,"planejamento":4,"comunicacao":3,"caso":2,"postura":1}', j);
  perform painel.salvar_ficha_entrevista(i_im2, '{"dominio":10,"analise":10,"planejamento":4,"comunicacao":3,"caso":2,"postura":1}', j);
  perform painel.salvar_ficha_entrevista(i_rs1, '{"dominio":9,"analise":8,"planejamento":3,"comunicacao":2,"caso":2,"postura":1}', j);
  perform painel.salvar_ficha_entrevista(i_rs2, '{"dominio":8,"analise":7,"planejamento":2,"comunicacao":2,"caso":1,"postura":0}', j);
  perform painel.salvar_ficha_entrevista(i_eli, '{"dominio":4,"analise":3,"planejamento":1,"comunicacao":1,"caso":1,"postura":0}', j);
  perform painel.salvar_ficha_entrevista(i_inc, '{"dominio":10,"analise":10,"planejamento":4,"comunicacao":3,"caso":2,"postura":1}', j);
  perform pg_temp.como(uz, 'z-cr@teste.local');
  perform painel.salvar_ficha_entrevista(i_im1, '{"dominio":10,"analise":10,"planejamento":4,"comunicacao":3,"caso":2,"postura":1}', j);
  perform painel.salvar_ficha_entrevista(i_im2, '{"dominio":10,"analise":10,"planejamento":4,"comunicacao":3,"caso":2,"postura":1}', j);
  perform painel.salvar_ficha_entrevista(i_rs1, '{"dominio":9,"analise":8,"planejamento":3,"comunicacao":2,"caso":2,"postura":1}', j);
  perform painel.salvar_ficha_entrevista(i_rs2, '{"dominio":8,"analise":7,"planejamento":2,"comunicacao":2,"caso":1,"postura":0}', j);
  perform painel.salvar_ficha_entrevista(i_eli, '{"dominio":4,"analise":3,"planejamento":1,"comunicacao":1,"caso":1,"postura":0}', j);
  -- i_inc fica com só 2 fichas (banca incompleta) de propósito: NÃO lança a 3ª.

  perform pg_temp.como(ustaff, 'staff-cr@teste.local');

  -- i_im1: ET=30 -> PF=75; i_im2: ET=30 -> PF=71; i_rs1: ET=25 -> PF=62; i_rs2: ET=20 -> PF=57; i_eli: ET=10 (<15) -> abaixo do corte.
  t := t || pg_temp.falha(format('select painel.publicar_resultado_final(%L, ''justificativa de teste'')', i_inc),
    'banca incompleta não publica', 'banca_incompleta');
  t := t || pg_temp.falha(format('select painel.publicar_resultado_final(gen_random_uuid(), ''justificativa de teste'')'),
    'inscrição inexistente', 'nao_encontrada');

  select painel.publicar_resultados_final_lote('B', 'pleno', 'Resultado final do Processo Seletivo (Anexo IV, item 23).') into qtd;
  t := t || pg_temp.igual(qtd::text, '5', 'lote publica os 5 com banca completa ou abaixo do corte (não publica o de banca incompleta)');

  -- republicação (idempotente)
  perform painel.publicar_resultado_final(i_im1, 'Republicação após conferência.');

  select count(*)::text into p from painel.publicacoes_final() where inscricao_id in (i_im1, i_im2, i_rs1, i_rs2, i_eli, i_inc);
  t := t || pg_temp.igual(p, '5', 'painel vê as 5 publicações (não inclui a de banca incompleta)');

  perform pg_temp.admin();
  select situacao || '|' || posicao::text into p from publico.resultados_candidato where inscricao_id = i_im1 and etapa = 'resultado_final';
  t := t || pg_temp.igual(p, 'classificado|1', 'imediata1: classificado, 1º lugar');
  select situacao || '|' || posicao::text into p from publico.resultados_candidato where inscricao_id = i_im2 and etapa = 'resultado_final';
  t := t || pg_temp.igual(p, 'classificado|2', 'imediata2: classificado, 2º lugar (2 vagas em B/Pleno)');
  select situacao || '|' || posicao::text into p from publico.resultados_candidato where inscricao_id = i_rs1 and etapa = 'resultado_final';
  t := t || pg_temp.igual(p, 'cadastro de reserva|3', 'reserva1: cadastro de reserva, 3º lugar');
  select situacao || '|' || posicao::text into p from publico.resultados_candidato where inscricao_id = i_rs2 and etapa = 'resultado_final';
  t := t || pg_temp.igual(p, 'cadastro de reserva|4', 'reserva2: cadastro de reserva, 4º lugar');
  select situacao || '|' || coalesce(posicao::text, '-') into p from publico.resultados_candidato where inscricao_id = i_eli and etapa = 'resultado_final';
  t := t || pg_temp.igual(p, 'eliminado na entrevista técnica|-', 'eliminado: ET abaixo de 15 pontos, sem posição (item 6.5.7)');
  select (motivacao is not null)::text into p from publico.resultados_candidato where inscricao_id = i_eli and etapa = 'resultado_final';
  t := t || pg_temp.igual(p, 'true', 'eliminado: motivação publicada');
  select count(*)::text into p from publico.resultados_candidato where inscricao_id = i_inc and etapa = 'resultado_final';
  t := t || pg_temp.igual(p, '0', 'banca incompleta: nada publicado');
  select count(*)::text into p from publico.resultados_candidato where inscricao_id = i_im1 and etapa = 'resultado_final';
  t := t || pg_temp.igual(p, '1', 'republicar não duplica');

  -- acesso: o candidato só vê o próprio resultado
  perform pg_temp.como(u_rs1, 'cr3@teste.local');
  select string_agg(distinct inscricao_id::text, ',') into p from publico.resultados_candidato where etapa = 'resultado_final';
  t := t || pg_temp.igual(p, i_rs1::text, 'reserva1 só vê o próprio resultado final');
  select situacao into p from publico.resultados_candidato where etapa = 'resultado_final';
  t := t || pg_temp.igual(p, 'cadastro de reserva', 'reserva1 vê a própria situação de cadastro de reserva');
  t := t || pg_temp.falha(format('select painel.publicar_resultado_final(%L, ''justificativa de teste'')', i_im1), 'candidato publica resultado final', 'Acesso restrito');
  t := t || pg_temp.falha('select * from painel.publicacoes_final()', 'candidato lê a visão da Comissão', 'Acesso restrito');

  -- auditoria (só as nossas inscrições de teste)
  perform pg_temp.admin();
  select count(*) into n from interno.auditoria
    where entidade = 'publico.resultados_candidato' and ator_id = ustaff
      and entidade_id in (i_im1::text, i_im2::text, i_rs1::text, i_rs2::text, i_eli::text);
  t := t || pg_temp.igual(n::text, '6', 'lote (5) + republicação de imediata1 (1) ficam na auditoria (6)');

  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
