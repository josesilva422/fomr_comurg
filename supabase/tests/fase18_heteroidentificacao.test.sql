-- Fase 18 · Heteroidentificação e listas específicas de PcD/cota racial (migração
-- 20261002100000_heteroidentificacao_e_listas_reserva.sql): interno.heteroidentificacoes,
-- painel.registrar_heteroidentificacao, painel.listar_heteroidentificacoes (item 10.4); e
-- painel.classificacao_final ganhando "cota_pcd"/"cota_racial" (itens 10.1, 10.2).
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
-- Uso remoto: colar no SQL Editor do Supabase (ou via MCP execute_sql).
do $teste$
declare
  ustaff constant uuid := 'f8000000-0000-0000-0000-00000000000f';
  ux constant uuid := 'f8000000-0000-0000-0000-000000000001';
  uy constant uuid := 'f8000000-0000-0000-0000-000000000002';
  uz constant uuid := 'f8000000-0000-0000-0000-000000000003';
  u_rac constant uuid := 'f8000000-0000-0000-0000-000000000011'; -- autodeclarado negro, convocado
  u_pcd constant uuid := 'f8000000-0000-0000-0000-000000000012'; -- PcD, convocado
  u_com constant uuid := 'f8000000-0000-0000-0000-000000000013'; -- sem cota, convocado
  u_nconv constant uuid := 'f8000000-0000-0000-0000-000000000014'; -- autodeclarado negro, NÃO convocado (AC baixo)
  i_rac uuid; i_pcd uuid; i_com uuid; i_nconv uuid;
  t text[] := '{}';
  p text; n integer; total integer; nf integer;
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
  -- Candidato habilitado para Grupo C Júnior (exp. mín. 12 meses; curso Administração aceito), com
  -- vínculo de 132 meses -> AC = 35 (teto de experiência). Devolve a inscrição, já submetida.
  execute $f$create function pg_temp.cand(p_uid uuid, p_n int, p_cpf text, p_cota_pcd boolean, p_cota_racial boolean, p_meses_vinculo int)
    returns uuid language plpgsql as $b$
    declare v_insc uuid; v_vinc uuid;
    begin
      execute 'reset role';
      perform set_config('request.jwt.claims', '', true);
      insert into auth.users (id, aud, role, email) values (p_uid, 'authenticated', 'authenticated', 'het' || p_n || '@teste.local');
      perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', 'het' || p_n || '@teste.local')::text, true);
      execute 'set local role authenticated';
      insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade)
        values (p_uid, 'Heteroidentificação Teste ' || p_n, p_cpf, '62999990000', '1985-05-05', 'brasileiro_nato');
      select id into v_insc from publico.inscricoes where candidato_id = (select id from publico.candidatos where user_id = p_uid);
      update publico.inscricoes set grupo = 'C', nivel = 'junior', curso_graduacao = 'Administração',
             grau_graduacao = 'bacharelado', instituicao_graduacao = 'UFG', data_colacao = '2005-12-15', formato_diploma = 'fisico',
             cota_pcd = p_cota_pcd, cota_racial = p_cota_racial,
             data_laudo = case when p_cota_pcd then (current_date - interval '1 month')::date end
        where id = v_insc;
      if p_cota_pcd then
        insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes)
          values (v_insc, 'laudo_pcd', v_insc || '/laudo_pcd/' || gen_random_uuid() || '.pdf', 'laudo.pdf', md5(v_insc::text) || md5('laudo' || p_n), 'application/pdf', 1000);
      end if;
      if p_cota_racial then
        insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes)
          values (v_insc, 'autodeclaracao_racial', v_insc || '/autodeclaracao_racial/' || gen_random_uuid() || '.pdf', 'autodecl.pdf', md5(v_insc::text) || md5('autodecl' || p_n), 'application/pdf', 1000);
      end if;
      insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao)
        values (v_insc, 'privado', 'Empresa Teste', 'Analista', (current_date - (p_meses_vinculo || ' months')::interval - interval '1 month')::date,
                (current_date - interval '1 month')::date, false, 'Atividades de teste do vínculo')
        returning id into v_vinc;
      insert into publico.documentos (inscricao_id, tipo, vinculo_id, storage_path, nome_original, sha256, mime, tamanho_bytes) values
        (v_insc, 'identidade', null, v_insc || '/identidade/' || gen_random_uuid() || '.pdf', 'rg.pdf', md5(v_insc::text) || md5('rg' || p_n), 'application/pdf', 1000),
        (v_insc, 'diploma_graduacao', null, v_insc || '/diploma_graduacao/' || gen_random_uuid() || '.pdf', 'diploma.pdf', md5(v_insc::text) || md5('dip' || p_n), 'application/pdf', 1000),
        (v_insc, 'experiencia_ctps', v_vinc, v_insc || '/experiencia_ctps/' || gen_random_uuid() || '.pdf', 'ctps.pdf', md5(v_vinc::text) || md5('exp' || p_n), 'application/pdf', 1000),
        (v_insc, 'comprovante_pix', null, v_insc || '/comprovante_pix/' || gen_random_uuid() || '.png', 'pix.png', md5(v_insc::text) || md5('pix' || p_n), 'image/png', 1000);
      perform publico.aceitar_declaracoes();
      perform publico.submeter_inscricao();
      return v_insc;
    end $b$
  $f$;

  update interno.configuracao set valor = to_jsonb((now() - interval '1 day')::text) where chave = 'inscricoes_abertura';
  update interno.configuracao set valor = to_jsonb((now() + interval '7 days')::text) where chave = 'inscricoes_encerramento';
  update interno.configuracao set valor = 'false'::jsonb where chave = 'painel_exige_login_seguro';

  insert into auth.users (id, aud, role, email) values
    (ustaff, 'authenticated', 'authenticated', 'staff-het@teste.local'),
    (ux, 'authenticated', 'authenticated', 'x-het@teste.local'), (uy, 'authenticated', 'authenticated', 'y-het@teste.local'),
    (uz, 'authenticated', 'authenticated', 'z-het@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email, perfil) values
    (ustaff, 'Comissão Heteroidentificação Teste', 'staff-het@teste.local', 'comissao'),
    (ux, 'Avaliador HET X', 'x-het@teste.local', 'comissao'), (uy, 'Avaliador HET Y', 'y-het@teste.local', 'comissao'),
    (uz, 'Avaliador HET Z', 'z-het@teste.local', 'comissao');

  -- Grupo C / Júnior: vagas = 1 -> corte de convocação (3x) = 3. Os 3 primeiros (rac, pcd, com) são convocados;
  -- o 4º (nconv), com vínculo bem mais curto (AC bem menor), fica de fora.
  i_rac := pg_temp.cand(u_rac, 1, '11144477735', false, true, 132);
  i_pcd := pg_temp.cand(u_pcd, 2, '52998224725', true, false, 120);
  i_com := pg_temp.cand(u_com, 3, '39053344705', false, false, 108);
  i_nconv := pg_temp.cand(u_nconv, 4, '22233344316', false, true, 2);

  -- banca completa só para o convocado autodeclarado negro (suficiente para os testes de acesso/listagem)
  perform pg_temp.como(ux, 'x-het@teste.local');
  perform painel.salvar_ficha_entrevista(i_rac, '{"dominio":8,"analise":8,"planejamento":3,"comunicacao":3,"caso":2,"postura":1}', j);
  perform pg_temp.como(uy, 'y-het@teste.local');
  perform painel.salvar_ficha_entrevista(i_rac, '{"dominio":8,"analise":8,"planejamento":3,"comunicacao":3,"caso":2,"postura":1}', j);
  perform pg_temp.como(uz, 'z-het@teste.local');
  perform painel.salvar_ficha_entrevista(i_rac, '{"dominio":8,"analise":8,"planejamento":3,"comunicacao":3,"caso":2,"postura":1}', j);

  perform pg_temp.como(ustaff, 'staff-het@teste.local');

  -- lista de pendentes de heteroidentificação: só os convocados com cota_racial (rac); nconv não aparece (não convocado)
  select string_agg(nome, ',') into p from painel.listar_heteroidentificacoes();
  t := t || pg_temp.igual(p, 'Heteroidentificação Teste 1', 'lista traz só o convocado autodeclarado negro');

  -- validações
  t := t || pg_temp.falha(format('select painel.registrar_heteroidentificacao(%L, true, ''curto'')', i_rac),
    'motivo curto', 'motivo_obrigatorio');
  t := t || pg_temp.falha(format('select painel.registrar_heteroidentificacao(%L, true, ''decisão fundamentada de teste'')', i_pcd),
    'candidato sem cota racial', 'nao_autodeclarado');
  t := t || pg_temp.falha(format('select painel.registrar_heteroidentificacao(%L, true, ''decisão fundamentada de teste'')', i_nconv),
    'candidato não convocado', 'nao_convocado');
  t := t || pg_temp.falha('select painel.registrar_heteroidentificacao(gen_random_uuid(), true, ''decisão fundamentada de teste'')',
    'inscrição inexistente', 'nao_encontrada');

  -- registro e consulta
  perform painel.registrar_heteroidentificacao(i_rac, true, 'Comissão de 5 membros confirmou a autodeclaração por videoconferência gravada.');
  select decisao into p from painel.listar_heteroidentificacoes() where inscricao_id = i_rac;
  t := t || pg_temp.igual(p, 'confirmada', 'heteroidentificação confirmada');

  -- redecisão (ex.: recurso à comissão recursal, item 10.4) atualiza, não duplica
  perform painel.registrar_heteroidentificacao(i_rac, false, 'Comissão recursal, de composição distinta, não confirmou a autodeclaração em segunda análise.');
  select decisao into p from painel.listar_heteroidentificacoes() where inscricao_id = i_rac;
  t := t || pg_temp.igual(p, 'nao_confirmada', 'redecisão (recurso) atualiza a mesma linha');
  perform pg_temp.admin();
  select count(*)::text into p from interno.heteroidentificacoes where inscricao_id = i_rac;
  t := t || pg_temp.igual(p, '1', 'uma linha só por inscrição, mesmo após redecisão');
  perform pg_temp.como(ustaff, 'staff-het@teste.local');

  -- classificacao_final expõe cota_pcd/cota_racial para a lista específica (itens 10.1/10.2)
  select x ->> 'cota_racial' into p from painel.classificacao_final('C', 'junior') x where x ->> 'inscricao_id' = i_rac::text;
  t := t || pg_temp.igual(p, 'true', 'classificacao_final marca cota_racial do convocado autodeclarado negro');
  select x ->> 'cota_pcd' into p from painel.classificacao_final('C', 'junior') x where x ->> 'inscricao_id' = i_pcd::text;
  t := t || pg_temp.igual(p, 'true', 'classificacao_final marca cota_pcd do convocado PcD');
  select x ->> 'cota_pcd' into p from painel.classificacao_final('C', 'junior') x where x ->> 'inscricao_id' = i_com::text;
  t := t || pg_temp.igual(p, 'false', 'candidato sem cota aparece com cota_pcd/cota_racial falsos');

  -- acesso
  perform pg_temp.como(u_rac, 'het1@teste.local');
  t := t || pg_temp.falha('select * from painel.listar_heteroidentificacoes()', 'candidato lista heteroidentificações', 'Acesso restrito');
  t := t || pg_temp.falha(format('select painel.registrar_heteroidentificacao(%L, true, ''decisão fundamentada de teste'')', i_rac),
    'candidato registra heteroidentificação', 'Acesso restrito');
  t := t || pg_temp.falha('select * from interno.heteroidentificacoes', 'candidato lê a tabela direto', 'permission denied');

  -- auditoria
  perform pg_temp.admin();
  select count(*) into n from interno.auditoria where entidade = 'interno.heteroidentificacoes' and ator_id = ustaff and entidade_id = i_rac::text;
  t := t || pg_temp.igual(n::text, '2', 'as duas decisões (inicial e redecisão) ficam na auditoria');

  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
