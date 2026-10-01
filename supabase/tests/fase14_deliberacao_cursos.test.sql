-- Fase 14 · Deliberação da Comissão sobre curso/certificação fora do catálogo exemplificativo (Anexo I, item 2.1;
-- migração 20261001100000_deliberacao_cursos_fora_catalogo.sql).
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
do $teste$
declare
  ustaff constant uuid := 'fd000000-0000-0000-0000-00000000000f';
  sstaff constant uuid := 'fe000000-0000-0000-0000-00000000000f';
  ua constant uuid := 'fd000000-0000-0000-0000-00000000000a';  -- Grupo A: curso fora do catálogo
  ub constant uuid := 'fd000000-0000-0000-0000-00000000000b';  -- Grupo A: curso dentro do catálogo (não deve aparecer)
  ia uuid; ib uuid; curso_a uuid; curso_b uuid;
  t text[] := '{}';
  n integer; total integer; nf integer;
  p text; av interno.avaliacoes_curriculares;
begin
  execute $f$create function pg_temp.como(p_uid uuid, p_email text) returns void language plpgsql as $b$
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email,
        'session_id', case when p_uid = 'fd000000-0000-0000-0000-00000000000f' then 'fe000000-0000-0000-0000-00000000000f' end)::text, true);
      execute 'set local role authenticated';
    end $b$
  $f$;
  -- NOTA: interno.calcular_avaliacao() só tem EXECUTE para o dono (postgres); qualquer chamada direta precisa
  -- vir depois de pg_temp.admin() (nunca direto após pg_temp.como(...)).
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
  execute $f$create function pg_temp.cria_candidato(p_uid uuid, p_email text, p_nome text, p_cpf text)
    returns uuid language plpgsql as $b$
    declare v_insc uuid; v_vinc uuid;
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
      execute 'set local role authenticated';
      insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade)
        values (p_uid, p_nome, p_cpf, '62999990000', '1988-03-14', 'brasileiro_nato');
      select id into v_insc from publico.inscricoes where candidato_id = (select id from publico.candidatos where user_id = p_uid);
      update publico.inscricoes set grupo = 'A', nivel = 'junior', curso_graduacao = 'Administração',
             grau_graduacao = 'bacharelado', instituicao_graduacao = 'UFG', data_colacao = '2010-12-15',
             formato_diploma = 'fisico' where id = v_insc;
      insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao)
        values (v_insc, 'privado', 'Empresa Teste', 'Analista', '2015-01-01', '2016-06-01', false, 'Atividades de teste do vínculo')
        returning id into v_vinc;
      insert into publico.documentos (inscricao_id, tipo, vinculo_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
        values (v_insc, 'experiencia_ctps', v_vinc, v_insc || '/experiencia_ctps/' || gen_random_uuid() || '.pdf', 'ctps.pdf', repeat('c', 64), 'application/pdf', 1000);
      return v_insc;
    end $b$
  $f$;

  update interno.configuracao set valor = to_jsonb((now() - interval '1 day')::text) where chave = 'inscricoes_abertura';
  update interno.configuracao set valor = to_jsonb((now() + interval '7 days')::text) where chave = 'inscricoes_encerramento';
  insert into auth.users (id, aud, role, email) values
    (ustaff, 'authenticated', 'authenticated', 'staff-del@teste.local'),
    (ua, 'authenticated', 'authenticated', 'del-a@teste.local'),
    (ub, 'authenticated', 'authenticated', 'del-b@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email) values (ustaff, 'Comissão Deliberação Teste', 'staff-del@teste.local');
  insert into interno.sessoes_painel (session_id, user_id) values (sstaff, ustaff);

  ia := pg_temp.cria_candidato(ua, 'del-a@teste.local', 'Deliberacao A Fora', '11122233043');
  ib := pg_temp.cria_candidato(ub, 'del-b@teste.local', 'Deliberacao B Dentro', '11122233124');

  -- A: curso de denominação que não bate com nenhum item do catálogo do Grupo A
  perform pg_temp.como(ua, 'del-a@teste.local');
  insert into publico.cursos_declarados (inscricao_id, tipo, denominacao, instituicao, carga_horaria, data_conclusao)
    values (ia, 'curso', 'Curso Fora Do Catalogo De Teste', 'Instituto Teste', 80, '2025-01-01') returning id into curso_a;
  insert into publico.documentos (inscricao_id, tipo, curso_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
    values (ia, 'certificado_curso', curso_a, ia || '/cursos/' || gen_random_uuid() || '.pdf', 'curso.pdf', repeat('a', 64), 'application/pdf', 1000);

  -- B: curso cuja denominação contém um item do catálogo do Grupo A ("Excel Avançado")
  perform pg_temp.como(ub, 'del-b@teste.local');
  insert into publico.cursos_declarados (inscricao_id, tipo, denominacao, instituicao, carga_horaria, data_conclusao)
    values (ib, 'curso', 'Excel Avançado', 'Instituto Teste', 80, '2025-01-01') returning id into curso_b;
  insert into publico.documentos (inscricao_id, tipo, curso_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
    values (ib, 'certificado_curso', curso_b, ib || '/cursos/' || gen_random_uuid() || '.pdf', 'curso.pdf', repeat('b', 64), 'application/pdf', 1000);

  perform pg_temp.admin();
  av := interno.calcular_avaliacao(ia);
  t := t || pg_temp.igual((select x ->> 'no_catalogo_do_grupo' from jsonb_array_elements(av.detalhamento #> '{cursos,itens}') x where x ->> 'id' = curso_a::text),
                          'false', 'curso de A está marcado como fora do catálogo');
  t := t || pg_temp.igual(av.pontos_cursos::text, '3.00', 'sem deliberação, o curso fora do catálogo ainda pontua (pendente de confirmação)');
  av := interno.calcular_avaliacao(ib);
  t := t || pg_temp.igual((select x ->> 'no_catalogo_do_grupo' from jsonb_array_elements(av.detalhamento #> '{cursos,itens}') x where x ->> 'id' = curso_b::text),
                          'true', 'curso de B está marcado como dentro do catálogo');

  ---------------------------------------------------------------- lista do painel
  perform pg_temp.como(ua, 'del-a@teste.local');
  t := t || pg_temp.falha('select * from painel.listar_cursos_fora_catalogo()', 'candidato lista cursos fora do catálogo', 'restrito');
  t := t || pg_temp.falha(format('select painel.decidir_curso_catalogo(%L, ''aceito'', ''motivo com mais de dez caracteres'')', curso_a), 'candidato decide o próprio curso', 'restrito');
  t := t || pg_temp.falha('select * from interno.deliberacoes_curso', 'candidato lê a tabela de deliberações', 'permission denied');

  perform pg_temp.como(ustaff, 'staff-del@teste.local');
  select count(*) into n from painel.listar_cursos_fora_catalogo() where curso_id = curso_a;
  t := t || pg_temp.igual(n::text, '1', 'o curso fora do catálogo aparece na lista para decisão');
  select count(*) into n from painel.listar_cursos_fora_catalogo() where curso_id = curso_b;
  t := t || pg_temp.igual(n::text, '0', 'o curso dentro do catálogo NÃO aparece na lista (não precisa de deliberação)');
  select decisao into p from painel.listar_cursos_fora_catalogo() where curso_id = curso_a;
  t := t || pg_temp.igual(p, null, 'ainda sem decisão registrada');

  ---------------------------------------------------------------- decidir: validações
  t := t || pg_temp.falha(format('select painel.decidir_curso_catalogo(%L, ''aceito'', ''curto'')', curso_a), 'decisão sem motivo suficiente', 'motivo_obrigatorio');
  t := t || pg_temp.falha(format('select painel.decidir_curso_catalogo(%L, ''talvez'', ''motivo com mais de dez caracteres'')', curso_a), 'decisão inválida', 'decisao_invalida');
  t := t || pg_temp.falha(format('select painel.decidir_curso_catalogo(''00000000-0000-0000-0000-000000000000'', ''aceito'', ''motivo com mais de dez caracteres'')'), 'curso inexistente', 'curso_nao_encontrado');

  ---------------------------------------------------------------- recusado: zera a pontuação do item
  select (painel.decidir_curso_catalogo(curso_a, 'recusado', 'Conteúdo não guarda relação com as atribuições do Grupo A.')).decisao into p;
  t := t || pg_temp.igual(p, 'recusado', 'Comissão recusa o curso com motivo');
  select decisao, motivo into p from painel.listar_cursos_fora_catalogo() where curso_id = curso_a;
  t := t || pg_temp.igual(p, 'recusado', 'o painel mostra a decisão registrada (ainda lida como "ustaff")');

  perform pg_temp.admin();
  av := interno.calcular_avaliacao(ia);
  t := t || pg_temp.igual(av.pontos_cursos::text, '0.00', 'curso recusado não pontua mais');
  t := t || pg_temp.igual((select x ->> 'motivo_rejeicao' from jsonb_array_elements(av.detalhamento #> '{cursos,itens}') x where x ->> 'id' = curso_a::text),
                          'Fora do catálogo exemplificativo (Anexo I, item 2.1); a Comissão deliberou não computar: Conteúdo não guarda relação com as atribuições do Grupo A..',
                          'motivo explica a recusa, citando o item 2.1');

  -- não consome a faixa de carga horária: um 2º curso de 80h fora do catálogo (sem deliberação ainda) pontua os 3,0 cheios
  perform pg_temp.como(ua, 'del-a@teste.local');
  insert into publico.cursos_declarados (inscricao_id, tipo, denominacao, instituicao, carga_horaria, data_conclusao)
    values (ia, 'curso', 'Curso Fora Do Catalogo De Teste Dois', 'Instituto Teste', 80, '2025-02-01') returning id into curso_a;
  insert into publico.documentos (inscricao_id, tipo, curso_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
    values (ia, 'certificado_curso', curso_a, ia || '/cursos/' || gen_random_uuid() || '.pdf', 'curso2.pdf', repeat('e', 64), 'application/pdf', 1000);

  perform pg_temp.admin();
  av := interno.calcular_avaliacao(ia);
  t := t || pg_temp.igual(av.pontos_cursos::text, '3.00', 'o item recusado não consome a faixa de 80h: o novo curso pontua os 3,0 cheios');

  ---------------------------------------------------------------- nova decisão (correção) prevalece: aceito
  perform pg_temp.como(ustaff, 'staff-del@teste.local');
  select (painel.decidir_curso_catalogo((select curso_id from painel.listar_cursos_fora_catalogo() where decisao = 'recusado' limit 1), 'aceito', 'Revisado: o conteúdo programático guarda correlação direta com o Grupo A.')).decisao into p;
  t := t || pg_temp.igual(p, 'aceito', 'Comissão corrige e aceita o curso, com novo motivo');

  perform pg_temp.admin();
  select count(*) into n from interno.deliberacoes_curso where curso_id = (select id from publico.cursos_declarados where denominacao = 'Curso Fora Do Catalogo De Teste');
  t := t || pg_temp.igual(n::text, '2', 'histórico preserva as duas decisões (recusado e depois aceito)');
  av := interno.calcular_avaliacao(ia);
  t := t || pg_temp.igual(av.pontos_cursos::text, '6.00', 'com os dois cursos aceitos (80h cada): 3,0 + 3,0 = 6,00');

  select count(*) into n from interno.auditoria where entidade = 'interno.deliberacoes_curso' and ator_id = ustaff;
  t := t || pg_temp.igual(n::text, '2', 'as duas decisões ficam na auditoria com o autor');

  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
