-- Fase 1 · Testes de segurança e regras de negócio (RLS, envio definitivo, trava de prazo, auditoria, storage, Pix).
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
-- O resultado aparece como uma exceção "RESULTADO_DOS_TESTES: N verificações, M falhas".
-- Uso local:  psql "$DATABASE_URL" -f supabase/tests/fase1_seguranca.test.sql
-- Uso remoto: colar no SQL Editor do Supabase (ou via MCP execute_sql).
do $teste$
declare
  ua constant uuid := 'a0000000-0000-0000-0000-00000000000a';
  ub constant uuid := 'b0000000-0000-0000-0000-00000000000b';
  uc constant uuid := 'c0000000-0000-0000-0000-00000000000c';
  ia uuid; ib uuid; ic uuid; va uuid; vb uuid; vc uuid;
  t text[] := '{}';
  n integer; total integer; nf integer;
  p text; st publico.status_inscricao;
begin
  ---------------------------------------------------------------- utilitários
  execute $f$create function pg_temp.como(p_uid uuid, p_email text) returns void language plpgsql as $b$
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
      execute 'set local role authenticated';
    end $b$
  $f$;
  execute $f$create function pg_temp.anonimo() returns void language plpgsql as $b$
    begin
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      execute 'set local role anon';
    end $b$
  $f$;
  execute $f$create function pg_temp.admin() returns void language plpgsql as $b$
    begin
      execute 'reset role';
      perform set_config('request.jwt.claims', '', true);
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
      if p_trecho is not null and (v_msg not ilike ('%' || p_trecho || '%')) and (coalesce(v_hint, '') not ilike ('%' || p_trecho || '%')) then
        return p_rotulo || ' -> falhou com outro erro: ' || v_msg;
      end if;
      return null;
    end $b$
  $f$;
  execute $f$create function pg_temp.passa(p_sql text, p_rotulo text) returns text language plpgsql as $b$
    begin
      execute p_sql; return null;
    exception when others then return p_rotulo || ' -> erro inesperado: ' || sqlerrm;
    end $b$
  $f$;
  execute $f$create function pg_temp.igual(p_atual text, p_esperado text, p_rotulo text) returns text language plpgsql as $b$
    begin
      if p_atual is not distinct from p_esperado then return null; end if;
      return p_rotulo || ' -> esperado [' || coalesce(p_esperado, 'NULL') || '] obtido [' || coalesce(p_atual, 'NULL') || ']';
    end $b$
  $f$;
  -- preenche uma inscrição completa e válida (executa com o papel atual, portanto sob RLS)
  execute $f$create function pg_temp.preenche(p_insc uuid, p_pix boolean) returns void language plpgsql as $b$
    declare v uuid;
    begin
      update publico.inscricoes set grupo = 'B', nivel = 'pleno', curso_graduacao = 'Administração',
             grau_graduacao = 'bacharelado', instituicao_graduacao = 'UFG', data_colacao = '2010-12-15',
             formato_diploma = 'fisico' where id = p_insc;
      insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao)
        values (p_insc, 'privado', 'Empresa Y', 'Analista', '2016-03-01', '2019-12-01', false, 'Planejamento e monitoramento de projetos')
        returning id into v;
      insert into publico.documentos (inscricao_id, tipo, vinculo_id, storage_path, nome_original, sha256, mime, tamanho_bytes) values
        (p_insc, 'identidade', null, p_insc || '/identidade/' || gen_random_uuid() || '.pdf', 'rg.pdf', repeat('a', 64), 'application/pdf', 1000),
        (p_insc, 'diploma_graduacao', null, p_insc || '/diploma_graduacao/' || gen_random_uuid() || '.pdf', 'diploma.pdf', repeat('b', 64), 'application/pdf', 1000),
        (p_insc, 'experiencia_ctps', v, p_insc || '/experiencia_ctps/' || gen_random_uuid() || '.pdf', 'ctps.pdf', repeat('c', 64), 'application/pdf', 1000);
      if p_pix then
        insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes)
          values (p_insc, 'comprovante_pix', p_insc || '/comprovante_pix/' || gen_random_uuid() || '.png', 'pix.png', repeat('d', 64), 'image/png', 1000);
      end if;
      perform publico.aceitar_declaracoes();
    end $b$
  $f$;

  ---------------------------------------------------------------- preparo (como administrador)
  update interno.configuracao set valor = to_jsonb((now() - interval '1 day')::text) where chave = 'inscricoes_abertura';
  update interno.configuracao set valor = to_jsonb((now() + interval '7 days')::text) where chave = 'inscricoes_encerramento';
  insert into auth.users (id, aud, role, email) values
    (ua, 'authenticated', 'authenticated', 'a@teste.local'),
    (ub, 'authenticated', 'authenticated', 'b@teste.local'),
    (uc, 'authenticated', 'authenticated', 'c@teste.local');
  select count(*) into n from publico.cursos_aceitos;
  t := t || pg_temp.igual(n::text, '339', 'seed: total de cursos aceitos');

  ---------------------------------------------------------------- anônimo
  perform pg_temp.anonimo();
  t := t || pg_temp.falha('select * from publico.candidatos', 'anon lê candidatos', 'permission denied');
  t := t || pg_temp.falha('select * from publico.inscricoes', 'anon lê inscrições', 'permission denied');
  t := t || pg_temp.falha('select * from publico.cursos_aceitos', 'anon lê cursos', 'permission denied');
  t := t || pg_temp.falha('select * from publico.verificar_inscricao()', 'anon executa verificar', 'permission denied');
  t := t || pg_temp.falha('select publico.submeter_inscricao()', 'anon executa submeter', 'permission denied');
  t := t || pg_temp.falha('select * from interno.auditoria', 'anon lê auditoria', 'permission denied');
  t := t || pg_temp.falha('select * from publico.dados_pagamento()', 'anon lê dados do Pix', 'permission denied');
  t := t || pg_temp.passa('select * from publico.periodo_inscricoes()', 'anon consulta o período');

  ---------------------------------------------------------------- candidato A: cadastro
  perform pg_temp.como(ua, 'a@teste.local');
  t := t || pg_temp.falha('select * from interno.auditoria', 'candidato lê auditoria', 'permission denied');
  t := t || pg_temp.falha('select * from interno.configuracao', 'candidato lê configuração', 'permission denied');
  select pix_chave into p from publico.dados_pagamento();
  t := t || pg_temp.igual(p, 'pss2026comurg@comurg.com.br', 'candidato lê a chave Pix pela função');
  select valor_centavos::text into p from publico.dados_pagamento();
  t := t || pg_temp.igual(p, '10000', 'taxa de R$ 100,00');
  t := t || pg_temp.falha('update interno.configuracao set valor = ''"2030-01-01T00:00:00Z"''', 'candidato altera configuração', 'permission denied');
  t := t || pg_temp.falha(format('insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade) values (%L, ''Maria Teste'', ''11111111111'', ''62999990000'', ''1988-03-14'', ''brasileiro_nato'')', ua), 'CPF com dígitos repetidos', 'violates check');
  t := t || pg_temp.falha(format('insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade) values (%L, ''Maria Teste'', ''52998224726'', ''62999990000'', ''1988-03-14'', ''brasileiro_nato'')', ua), 'CPF com dígito verificador errado', 'violates check');
  t := t || pg_temp.falha(format('insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade) values (%L, ''Maria'', ''52998224725'', ''62999990000'', ''1988-03-14'', ''brasileiro_nato'')', ua), 'nome sem sobrenome', 'violates check');
  t := t || pg_temp.falha(format('insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade) values (%L, ''Maria Teste'', ''52998224725'', ''6299'', ''1988-03-14'', ''brasileiro_nato'')', ua), 'telefone inválido', 'violates check');
  t := t || pg_temp.passa(format('insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade) values (%L, ''Maria Teste Silva'', ''52998224725'', ''62999990000'', ''1988-03-14'', ''brasileiro_nato'')', ua), 'A cria candidato');
  select count(*) into n from publico.inscricoes;
  t := t || pg_temp.igual(n::text, '1', 'inscrição criada automaticamente (1)');
  select id into ia from publico.inscricoes;
  select email into p from publico.candidatos;
  t := t || pg_temp.igual(p, 'a@teste.local', 'e-mail vem da conta autenticada');
  t := t || pg_temp.falha('update publico.candidatos set user_id = ''b0000000-0000-0000-0000-00000000000b''', 'A troca o dono do cadastro', 'permission denied');
  t := t || pg_temp.falha('update publico.candidatos set email = ''outro@x.com''', 'A altera o e-mail direto', 'permission denied');
  t := t || pg_temp.falha('insert into publico.inscricoes (candidato_id) select id from publico.candidatos', 'A cria 2ª inscrição', 'permission denied');
  t := t || pg_temp.falha('delete from publico.inscricoes', 'A apaga inscrição', 'permission denied');
  t := t || pg_temp.falha('update publico.inscricoes set status = ''homologada''', 'A altera o status', 'permission denied');
  t := t || pg_temp.falha('update publico.inscricoes set submetida_em = now()', 'A altera submetida_em', 'permission denied');
  t := t || pg_temp.falha('update publico.inscricoes set declaracoes_aceitas_em = now()', 'A grava o aceite direto', 'permission denied');

  ---------------------------------------------------------------- candidato B e isolamento
  perform pg_temp.como(ub, 'b@teste.local');
  t := t || pg_temp.falha(format('insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade) values (%L, ''Bruno Teste Souza'', ''52998224725'', ''62988880000'', ''1990-05-20'', ''brasileiro_nato'')', ub), 'CPF repetido entre candidatos', 'duplicate key');
  t := t || pg_temp.falha(format('insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade) values (%L, ''Bruno Teste Souza'', ''39053344705'', ''62988880000'', ''1990-05-20'', ''brasileiro_nato'')', ua), 'B cadastra em nome de A', 'row-level security');
  t := t || pg_temp.passa(format('insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade) values (%L, ''Bruno Teste Souza'', ''39053344705'', ''62988880000'', ''1990-05-20'', ''brasileiro_nato'')', ub), 'B cria candidato');
  select count(*) into n from publico.candidatos;
  t := t || pg_temp.igual(n::text, '1', 'B enxerga só o próprio candidato');
  select count(*) into n from publico.inscricoes where id = ia;
  t := t || pg_temp.igual(n::text, '0', 'B não enxerga a inscrição de A');
  select id into ib from publico.inscricoes;
  t := t || pg_temp.passa(format('update publico.inscricoes set grupo = ''A'' where id = %L', ia), 'B tenta alterar a inscrição de A (RLS filtra: 0 linhas)');
  perform pg_temp.admin();
  select grupo::text into p from publico.inscricoes where id = ia;
  t := t || pg_temp.igual(p, null, 'inscrição de A não foi alterada por B');

  -- B cria um vínculo (usado para testar referência cruzada)
  perform pg_temp.como(ub, 'b@teste.local');
  insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao)
    values (ib, 'privado', 'Empresa B', 'Analista', '2020-01-01', '2021-01-01', false, 'Atividades do vínculo de B') returning id into vb;
  t := t || pg_temp.passa(format('insert into storage.objects (bucket_id, name) values (''documentos'', %L)', ib || '/identidade/b.pdf'), 'B envia arquivo na própria pasta');

  ---------------------------------------------------------------- candidato A: vínculos, documentos, storage
  perform pg_temp.como(ua, 'a@teste.local');
  t := t || pg_temp.falha(format('insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao) values (%L, ''privado'', ''Empresa X'', ''Analista'', ''2020-01-01'', ''2019-01-01'', false, ''Descrição do vínculo'')', ia), 'fim antes do início', 'violates check');
  t := t || pg_temp.falha(format('insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao) values (%L, ''privado'', ''Empresa X'', ''Analista'', ''2020-01-01'', ''2021-01-01'', true, ''Descrição do vínculo'')', ia), 'ativo com data de fim', 'violates check');
  t := t || pg_temp.falha(format('insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao) values (%L, ''privado'', ''Empresa X'', ''Analista'', ''2020-01-15'', ''2021-01-01'', false, ''Descrição do vínculo'')', ia), 'início fora do dia 1', 'violates check');
  t := t || pg_temp.falha(format('insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao) values (%L, ''privado'', ''Empresa X'', ''Analista'', ''2020-01-01'', ''2021-01-01'', false, ''Descrição do vínculo'')', ib), 'A cria vínculo na inscrição de B', 'row-level security');
  insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao)
    values (ia, 'privado', 'Empresa X', 'Analista', '2020-01-01', '2022-12-01', false, 'Planejamento e controle de projetos') returning id into va;
  select count(*) into n from publico.vinculos_declarados;
  t := t || pg_temp.igual(n::text, '1', 'A enxerga só os próprios vínculos');
  t := t || pg_temp.passa(format('delete from publico.vinculos_declarados where id = %L', vb), 'A tenta apagar vínculo de B (RLS filtra: 0 linhas)');
  perform pg_temp.admin();
  select count(*) into n from publico.vinculos_declarados where id = vb;
  t := t || pg_temp.igual(n::text, '1', 'vínculo de B continua existindo');
  perform pg_temp.como(ua, 'a@teste.local');

  t := t || pg_temp.passa(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''identidade'', %L, ''rg.pdf'', repeat(''a'', 64), ''application/pdf'', 1000)', ia, ia || '/identidade/' || gen_random_uuid() || '.pdf'), 'A envia identidade');
  t := t || pg_temp.passa(format('insert into publico.documentos (inscricao_id, tipo, vinculo_id, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''experiencia_ctps'', %L, %L, ''ctps.pdf'', repeat(''c'', 64), ''application/pdf'', 1000)', ia, va, ia || '/experiencia_ctps/' || gen_random_uuid() || '.pdf'), 'A envia CTPS ligada ao próprio vínculo');
  t := t || pg_temp.passa(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''cpf'', %L, ''cpf.pdf'', repeat(''e'', 64), ''application/pdf'', 1000)', ia, ia || '/cpf/' || gen_random_uuid() || '.pdf'), 'A envia CPF');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''identidade'', %L, ''rg.pdf'', repeat(''a'', 64), ''application/pdf'', 1000)', ib, ib || '/identidade/' || gen_random_uuid() || '.pdf'), 'A envia documento na inscrição de B', 'row-level security');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''identidade'', %L, ''rg.pdf'', repeat(''a'', 64), ''application/pdf'', 1000)', ia, ib || '/identidade/' || gen_random_uuid() || '.pdf'), 'caminho de outra inscrição', 'violates check');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, vinculo_id, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''experiencia_ctps'', %L, %L, ''ctps.pdf'', repeat(''c'', 64), ''application/pdf'', 1000)', ia, vb, ia || '/experiencia_ctps/' || gen_random_uuid() || '.pdf'), 'documento ligado ao vínculo de B', 'row-level security');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''identidade'', %L, ''x.exe'', repeat(''a'', 64), ''application/x-msdownload'', 1000)', ia, ia || '/identidade/' || gen_random_uuid() || '.exe'), 'tipo de arquivo não aceito', 'violates check');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''identidade'', %L, ''grande.pdf'', repeat(''a'', 64), ''application/pdf'', 10485761)', ia, ia || '/identidade/' || gen_random_uuid() || '.pdf'), 'arquivo maior que 10 MB', 'violates check');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''identidade'', %L, ''rg.pdf'', ''zzz'', ''application/pdf'', 1000)', ia, ia || '/identidade/' || gen_random_uuid() || '.pdf'), 'hash SHA-256 inválido', 'violates check');
  select count(*) into n from publico.documentos;
  t := t || pg_temp.igual(n::text, '3', 'A enxerga só os próprios documentos');
  t := t || pg_temp.falha('update publico.documentos set tipo = ''laudo_pcd''', 'A altera o tipo de um documento', 'permission denied');
  t := t || pg_temp.falha('update publico.documentos set storage_path = ''x''', 'A altera o caminho de um documento', 'permission denied');
  t := t || pg_temp.falha('delete from publico.documentos', 'A apaga documento', 'permission denied');
  t := t || pg_temp.passa('update publico.documentos set ativo = false where tipo = ''cpf''', 'A remove (soft) um documento');
  select (removido_em is not null)::text into p from publico.documentos where tipo = 'cpf';
  t := t || pg_temp.igual(p, 'true', 'removido_em preenchido pelo servidor');
  t := t || pg_temp.falha('update publico.documentos set ativo = true where tipo = ''cpf''', 'reativar documento removido', 'reativado');

  t := t || pg_temp.passa(format('insert into storage.objects (bucket_id, name) values (''documentos'', %L)', ia || '/identidade/a.pdf'), 'A envia arquivo na própria pasta');
  t := t || pg_temp.falha(format('insert into storage.objects (bucket_id, name) values (''documentos'', %L)', ib || '/identidade/a.pdf'), 'A envia arquivo na pasta de B', 'row-level security');
  t := t || pg_temp.falha('insert into storage.objects (bucket_id, name) values (''documentos'', ''qualquer/coisa.pdf'')', 'A envia arquivo fora da própria pasta', 'row-level security');
  t := t || pg_temp.passa(format('update storage.objects set name = %L where bucket_id = ''documentos''', ia || '/identidade/renomeado.pdf'), 'A tenta renomear arquivo (sem policy: 0 linhas)');
  select count(*) into n from storage.objects where name like '%renomeado%';
  t := t || pg_temp.igual(n::text, '0', 'arquivo não foi renomeado');
  select count(*) into n from storage.objects where bucket_id = 'documentos';
  t := t || pg_temp.igual(n::text, '1', 'A enxerga só os próprios arquivos');

  ---------------------------------------------------------------- pendências e envio
  select string_agg(codigo, ',') into p from publico.verificar_inscricao();
  t := t || pg_temp.igual((p like '%grupo_nivel_ausente%' and p like '%graduacao_incompleta%' and p like '%comprovante_pix_ausente%' and p like '%declaracoes_nao_aceitas%' and p like '%diploma_ausente%')::text, 'true', 'pendências da inscrição vazia: ' || coalesce(p, 'nenhuma'));
  t := t || pg_temp.falha('select publico.submeter_inscricao()', 'enviar com pendências', 'inscricao_com_pendencias');

  update publico.inscricoes set grupo = 'A', nivel = 'senior', curso_graduacao = 'Administração', grau_graduacao = 'bacharelado',
         instituicao_graduacao = 'UFG', data_colacao = '2010-12-15', formato_diploma = 'fisico' where id = ia;
  select string_agg(codigo, ',') into p from publico.verificar_inscricao();
  t := t || pg_temp.igual((p like '%curso_nao_aceito%' and p like '%lideranca_ausente%')::text, 'true', 'Grupo A Sênior: curso não aceito e liderança ausente: ' || coalesce(p, 'nenhuma'));
  update publico.inscricoes set formato_diploma = 'digital', codigo_diploma_digital = null where id = ia;
  select string_agg(codigo, ',') into p from publico.verificar_inscricao();
  t := t || pg_temp.igual((p like '%diploma_digital_sem_codigo%')::text, 'true', 'diploma digital sem código');
  update publico.inscricoes set cota_pcd = true, cota_racial = true, solicitou_isencao = true where id = ia;
  select string_agg(codigo, ',') into p from publico.verificar_inscricao();
  t := t || pg_temp.igual((p like '%laudo_ausente%' and p like '%autodeclaracao_ausente%' and p like '%isencao_incompleta%' and p not like '%comprovante_pix_ausente%')::text, 'true', 'reservas e isenção sem documentos: ' || coalesce(p, 'nenhuma'));
  update publico.inscricoes set cota_pcd = false, cota_racial = false, solicitou_isencao = false where id = ia;
  update publico.candidatos set data_nascimento = '2015-01-01';
  select string_agg(codigo, ',') into p from publico.verificar_inscricao();
  t := t || pg_temp.igual((p like '%menor_de_18%')::text, 'true', 'menor de 18 anos');
  update publico.candidatos set data_nascimento = '1988-03-14';

  perform pg_temp.preenche(ia, true);
  select count(*) into n from publico.verificar_inscricao();
  select coalesce(string_agg(codigo, ','), 'nenhuma') into p from publico.verificar_inscricao();
  t := t || pg_temp.igual(n::text, '0', 'inscrição completa sem pendências (restantes: ' || p || ')');
  select publico.submeter_inscricao() into st;
  t := t || pg_temp.igual(st::text, 'submetida', 'envio da inscrição completa');
  select (submetida_em is not null)::text into p from publico.inscricoes;
  t := t || pg_temp.igual(p, 'true', 'submetida_em preenchido pelo servidor');
  -- ENVIO DEFINITIVO: depois de enviada, o candidato só lê
  t := t || pg_temp.falha('select publico.submeter_inscricao()', 'reenviar depois de enviada', 'inscricao_indisponivel');
  t := t || pg_temp.falha('select publico.aceitar_declaracoes()', 'aceitar declarações depois de enviada', 'inscricao_indisponivel');
  t := t || pg_temp.passa('update publico.inscricoes set grupo = ''C''', 'A tenta alterar inscrição enviada (RLS filtra: 0 linhas)');
  select grupo::text into p from publico.inscricoes;
  t := t || pg_temp.igual(p, 'B', 'inscrição enviada não foi alterada');
  t := t || pg_temp.passa('update publico.candidatos set telefone = ''62900001111''', 'A tenta alterar o cadastro depois de enviar (RLS filtra: 0 linhas)');
  select telefone into p from publico.candidatos;
  t := t || pg_temp.igual(p, '62999990000', 'cadastro enviado não foi alterado');
  t := t || pg_temp.falha(format('insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao) values (%L, ''privado'', ''Empresa Z'', ''Analista'', ''2020-01-01'', ''2021-01-01'', false, ''Vínculo incluído depois'')', ia), 'incluir vínculo depois de enviada', 'row-level security');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''cpf'', %L, ''cpf2.pdf'', repeat(''e'', 64), ''application/pdf'', 1000)', ia, ia || '/cpf/' || gen_random_uuid() || '.pdf'), 'incluir documento depois de enviada', 'row-level security');
  t := t || pg_temp.passa('update publico.documentos set ativo = false', 'A tenta remover documentos depois de enviar (RLS filtra: 0 linhas)');
  select count(*) into n from publico.documentos where ativo;
  t := t || pg_temp.igual((n >= 6)::text, 'true', 'documentos enviados continuam ativos');
  t := t || pg_temp.passa('delete from publico.vinculos_declarados', 'A tenta apagar vínculos depois de enviar (RLS filtra: 0 linhas)');
  select count(*) into n from publico.vinculos_declarados;
  t := t || pg_temp.igual((n >= 2)::text, 'true', 'vínculos enviados continuam existindo');
  t := t || pg_temp.falha(format('insert into storage.objects (bucket_id, name) values (''documentos'', %L)', ia || '/identidade/depois.pdf'), 'enviar arquivo depois de enviada', 'row-level security');
  select status::text into p from publico.inscricoes;
  t := t || pg_temp.igual(p, 'submetida', 'status da inscrição enviada');
  select count(*) into n from publico.documentos;
  t := t || pg_temp.igual((n > 0)::text, 'true', 'candidato continua LENDO a inscrição enviada');

  ---------------------------------------------------------------- B: pedido de isenção (sem Pix)
  perform pg_temp.como(ub, 'b@teste.local');
  perform pg_temp.preenche(ib, false);
  insert into publico.documentos (inscricao_id, tipo, vinculo_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
    values (ib, 'experiencia_ctps', vb, ib || '/experiencia_ctps/' || gen_random_uuid() || '.pdf', 'ctps-b.pdf', repeat('9', 64), 'application/pdf', 1000);
  update publico.inscricoes set solicitou_isencao = true, justificativa_isencao = 'Situação de vulnerabilidade comprovada.' where id = ib;
  select string_agg(codigo, ',') into p from publico.verificar_inscricao();
  t := t || pg_temp.igual((p like '%isencao_incompleta%')::text, 'true', 'isenção sem requerimento anexado');
  insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes)
    values (ib, 'requerimento_isencao', ib || '/requerimento_isencao/' || gen_random_uuid() || '.pdf', 'req.pdf', repeat('f', 64), 'application/pdf', 1000);
  select publico.submeter_inscricao() into st;
  t := t || pg_temp.igual(st::text, 'aguardando_isencao', 'com isenção o status é aguardando_isencao');
  t := t || pg_temp.passa('update publico.inscricoes set justificativa_isencao = ''alterada depois''', 'B tenta alterar depois de enviar (RLS filtra: 0 linhas)');
  select justificativa_isencao into p from publico.inscricoes;
  t := t || pg_temp.igual(p, 'Situação de vulnerabilidade comprovada.', 'pedido de isenção enviado não foi alterado');

  -- C: candidata ainda em rascunho (usada para testar a trava de prazo)
  perform pg_temp.como(uc, 'c@teste.local');
  t := t || pg_temp.passa(format('insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade) values (%L, ''Carla Teste Lima'', ''11144477735'', ''62977770000'', ''1992-07-01'', ''brasileiro_nato'')', uc), 'C cria candidato');
  select id into ic from publico.inscricoes;
  insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao)
    values (ic, 'privado', 'Empresa C', 'Analista', '2020-01-01', '2021-01-01', false, 'Atividades do vínculo de C') returning id into vc;
  insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes)
    values (ic, 'identidade', ic || '/identidade/' || gen_random_uuid() || '.pdf', 'rg-c.pdf', repeat('7', 64), 'application/pdf', 1000);
  t := t || pg_temp.passa('update publico.candidatos set telefone = ''62977771111''', 'C (rascunho) altera o cadastro');

  ---------------------------------------------------------------- trava de prazo (servidor)
  perform pg_temp.admin();
  update interno.configuracao set valor = to_jsonb((now() - interval '1 hour')::text) where chave = 'inscricoes_encerramento';
  perform pg_temp.como(uc, 'c@teste.local');
  t := t || pg_temp.falha(format('update publico.inscricoes set grupo = ''B'' where id = %L', ic), 'alterar inscrição após o encerramento', 'inscricoes_fora_do_periodo');
  t := t || pg_temp.falha(format('insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao) values (%L, ''privado'', ''Empresa Z'', ''Analista'', ''2020-01-01'', ''2021-01-01'', false, ''Vínculo incluído tarde'')', ic), 'incluir vínculo após o encerramento', 'inscricoes_fora_do_periodo');
  t := t || pg_temp.falha(format('update publico.vinculos_declarados set cargo = ''Gerente'' where id = %L', vc), 'alterar vínculo após o encerramento', 'inscricoes_fora_do_periodo');
  t := t || pg_temp.falha(format('delete from publico.vinculos_declarados where id = %L', vc), 'apagar vínculo após o encerramento', 'inscricoes_fora_do_periodo');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''cpf'', %L, ''cpf.pdf'', repeat(''e'', 64), ''application/pdf'', 1000)', ic, ic || '/cpf/' || gen_random_uuid() || '.pdf'), 'incluir documento após o encerramento', 'inscricoes_fora_do_periodo');
  t := t || pg_temp.falha('update publico.documentos set ativo = false where tipo = ''identidade''', 'remover documento após o encerramento', 'inscricoes_fora_do_periodo');
  t := t || pg_temp.falha('update publico.candidatos set telefone = ''62911112222''', 'alterar cadastro após o encerramento', 'inscricoes_fora_do_periodo');
  t := t || pg_temp.falha('select publico.aceitar_declaracoes()', 'aceitar declarações após o encerramento', 'inscricoes_fora_do_periodo');
  t := t || pg_temp.falha('select publico.submeter_inscricao()', 'enviar após o encerramento', 'pendência');
  t := t || pg_temp.falha(format('insert into storage.objects (bucket_id, name) values (''documentos'', %L)', ic || '/identidade/tarde.pdf'), 'enviar arquivo após o encerramento', 'row-level security');
  select count(*) into n from publico.documentos;
  t := t || pg_temp.igual((n > 0)::text, 'true', 'depois do prazo a candidata em rascunho ainda LÊ os próprios documentos');
  perform pg_temp.como(ua, 'a@teste.local');
  select count(*) into n from publico.documentos;
  t := t || pg_temp.igual((n > 0)::text, 'true', 'depois do prazo o candidato com inscrição enviada ainda LÊ os documentos');
  perform pg_temp.admin();
  t := t || pg_temp.passa(format('update publico.inscricoes set updated_at = now() where id = %L', ia), 'serviço interno (sem JWT) não é bloqueado pela trava');

  ---------------------------------------------------------------- auditoria
  select count(*) into n from interno.auditoria where ator_id = ua and entidade = 'publico.vinculos_declarados';
  t := t || pg_temp.igual((n > 0)::text, 'true', 'auditoria registra as ações de A com o ator');
  select count(*) into n from interno.auditoria where entidade = 'publico.candidatos' and acao = 'INSERT';
  t := t || pg_temp.igual(n::text, '3', 'auditoria dos três cadastros');
  t := t || pg_temp.falha('update interno.auditoria set acao = ''x''', 'alterar auditoria', 'append-only');
  t := t || pg_temp.falha('delete from interno.auditoria', 'apagar auditoria', 'append-only');
  t := t || pg_temp.falha('truncate interno.auditoria', 'truncar auditoria', 'append-only');

  ---------------------------------------------------------------- resultado (a exceção desfaz TUDO)
  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
