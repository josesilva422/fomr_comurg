-- Fase 3 (início) · Testes da convocação para entrevista (edital itens 6.4.4 e 6.5.1) e do cronograma
-- (Anexo IV), expostos por painel.listar_avaliacoes()/painel.listar_cronograma()
-- (migração 20260922170000_convocacao_e_cronograma.sql).
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
-- Uso local:  psql "$DATABASE_URL" -f supabase/tests/fase3_convocacao.test.sql
-- Uso remoto: colar no SQL Editor do Supabase (ou via MCP execute_sql).
do $teste$
declare
  ustaff constant uuid := 'd0000000-0000-0000-0000-00000000000d';
  ua constant uuid := 'e0000000-0000-0000-0000-00000000000a';
  ub constant uuid := 'e0000000-0000-0000-0000-00000000000b';
  uc constant uuid := 'e0000000-0000-0000-0000-00000000000c';
  ud constant uuid := 'e0000000-0000-0000-0000-00000000000d';
  ue constant uuid := 'e0000000-0000-0000-0000-00000000000e';
  uf constant uuid := 'e0000000-0000-0000-0000-00000000000f';
  t text[] := '{}';
  n integer; v_total integer; nf integer;
  p text;
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
  -- Cria um candidato Grupo A / Júnior completo, com um vínculo (p_inicio a p_fim, não ativo) e
  -- p_n_especializacoes títulos de especialização (360h, com documento) — cada um vale 2,0 pts, sem
  -- limite de quantidade (edital atualizado 22/09/2026). Sem cursos declarados. Envia a inscrição.
  execute $f$create function pg_temp.cria_candidato(p_uid uuid, p_email text, p_nome text, p_cpf text, p_inicio date, p_fim date, p_n_especializacoes int)
    returns uuid language plpgsql as $b$
    declare v_insc uuid; v_vinc uuid; v_tit uuid; i int;
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
        values (v_insc, 'privado', 'Empresa Teste', 'Analista', p_inicio, p_fim, false, 'Atividades de teste do vínculo')
        returning id into v_vinc;
      insert into publico.documentos (inscricao_id, tipo, vinculo_id, storage_path, nome_original, sha256, mime, tamanho_bytes) values
        (v_insc, 'identidade', null, v_insc || '/identidade/' || gen_random_uuid() || '.pdf', 'rg.pdf', repeat('a', 64), 'application/pdf', 1000),
        (v_insc, 'diploma_graduacao', null, v_insc || '/diploma_graduacao/' || gen_random_uuid() || '.pdf', 'diploma.pdf', repeat('b', 64), 'application/pdf', 1000),
        (v_insc, 'experiencia_ctps', v_vinc, v_insc || '/experiencia_ctps/' || gen_random_uuid() || '.pdf', 'ctps.pdf', repeat('c', 64), 'application/pdf', 1000),
        (v_insc, 'comprovante_pix', null, v_insc || '/comprovante_pix/' || gen_random_uuid() || '.png', 'pix.png', repeat('d', 64), 'image/png', 1000);
      for i in 1..p_n_especializacoes loop
        insert into publico.titulos_declarados (inscricao_id, tipo, denominacao, instituicao, carga_horaria, data_conclusao)
          values (v_insc, 'especializacao', 'Pós ' || i, 'FGV', 400, '2020-01-01') returning id into v_tit;
        insert into publico.documentos (inscricao_id, tipo, titulo_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
          values (v_insc, 'diploma_pos', v_tit, v_insc || '/diploma_pos/' || gen_random_uuid() || '.pdf', 'pos.pdf', repeat(i::text, 64), 'application/pdf', 1000);
      end loop;
      perform publico.aceitar_declaracoes();
      perform publico.submeter_inscricao();
      return v_insc;
    end $b$
  $f$;

  ---------------------------------------------------------------- preparo (como administrador)
  update interno.configuracao set valor = to_jsonb((now() - interval '1 day')::text) where chave = 'inscricoes_abertura';
  update interno.configuracao set valor = to_jsonb((now() + interval '7 days')::text) where chave = 'inscricoes_encerramento';
  insert into auth.users (id, aud, role, email) values
    (ustaff, 'authenticated', 'authenticated', 'staff@teste.local'),
    (ua, 'authenticated', 'authenticated', 'ea@teste.local'),
    (ub, 'authenticated', 'authenticated', 'eb@teste.local'),
    (uc, 'authenticated', 'authenticated', 'ec@teste.local'),
    (ud, 'authenticated', 'authenticated', 'ed@teste.local'),
    (ue, 'authenticated', 'authenticated', 'ee@teste.local'),
    (uf, 'authenticated', 'authenticated', 'ef@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email, perfil) values (ustaff, 'Fiscal Teste', 'staff@teste.local', 'comissao');

  -- Grupo A / Júnior, vagas = 1 (seed interno.vagas) => corte da convocação = 1 × 3 = 3 (item 6.5.1).
  -- Todos com o MESMO vínculo (2015-01 a 2026-01 = 133 meses => excedente 121m => 35,0 pts de experiência,
  -- o teto do critério), diferenciados só pela Formação (especializações, 2,0 pts cada, sem limite de
  -- quantidade — edital atualizado 22/09/2026), para todos ficarem ACIMA do mínimo de 35 pts (item 6.4.4):
  --   A: 35 + 5×2,0 = 45,00  (1º)
  --   B: 35 + 3×2,0 = 41,00  (2º)
  --   C: 35 + 1×2,0 = 37,00  (3º — EMPATADO)
  --   D: 35 + 1×2,0 = 37,00  (3º — EMPATADO, mesmo total de C)
  --   E: 35 + 0      = 35,00  (5º — RANK pula o 4 por causa do empate; fora do corte de 3)
  -- F: vínculo curto (13 meses => excedente 1m => 5,0 pts, sem especialização) => total 5,00, ABAIXO de
  --    35 — nem entra na disputa da convocação (item 6.4.4), independente de haver vaga sobrando.
  perform pg_temp.cria_candidato(ua, 'ea@teste.local', 'Convocacao A Primeiro', '12345678143', '2015-01-01', '2026-01-01', 5);
  perform pg_temp.cria_candidato(ub, 'eb@teste.local', 'Convocacao B Segundo', '23456789254', '2015-01-01', '2026-01-01', 3);
  perform pg_temp.cria_candidato(uc, 'ec@teste.local', 'Convocacao C Empate', '34567890337', '2015-01-01', '2026-01-01', 1);
  perform pg_temp.cria_candidato(ud, 'ed@teste.local', 'Convocacao D Empate', '45678901400', '2015-01-01', '2026-01-01', 1);
  perform pg_temp.cria_candidato(ue, 'ee@teste.local', 'Convocacao E Fora Do Corte', '56789012575', '2015-01-01', '2026-01-01', 0);
  perform pg_temp.cria_candidato(uf, 'ef@teste.local', 'Convocacao F Abaixo De 35', '67890123620', '2025-01-01', '2026-01-01', 0);

  ---------------------------------------------------------------- painel: convocação
  perform pg_temp.como(ustaff, 'staff@teste.local');
  select string_agg(nome || ':' || total::text || ':' || coalesce(posicao::text, 'null') || ':' || convocado::text, ' | ' order by total desc, nome)
    into p
    from painel.listar_avaliacoes()
    where grupo = 'A' and nivel = 'junior' and nome like 'Convocacao %';
  t := t || pg_temp.igual(
    p,
    'Convocacao A Primeiro:45.00:1:true | Convocacao B Segundo:41.00:2:true | Convocacao C Empate:37.00:3:true | Convocacao D Empate:37.00:3:true | Convocacao E Fora Do Corte:35.00:5:false | Convocacao F Abaixo De 35:5.00:null:false',
    'convocação Grupo A/Júnior (vagas=1, corte=3): ranking, empate na última posição e piso de 35 pts — obtido: ' || coalesce(p, 'nenhuma')
  );

  select count(*) into n from painel.listar_avaliacoes() where grupo = 'A' and nivel = 'junior' and nome like 'Convocacao %' and convocado;
  t := t || pg_temp.igual(n::text, '4', 'os 2 empatados no 3º lugar contam os 2 — total de 4 convocados, não 3 (item 6.5.1, "incluindo empatados na última posição")');

  select convocado::text into p from painel.listar_avaliacoes() where nome = 'Convocacao F Abaixo De 35';
  t := t || pg_temp.igual(p, 'false', 'abaixo de 35 pts não é convocado mesmo sobrando vaga na fila (item 6.4.4)');

  ---------------------------------------------------------------- acesso restrito
  perform pg_temp.como(ua, 'ea@teste.local');
  begin
    perform painel.listar_avaliacoes();
    t := t || array['candidato comum acessou painel.listar_avaliacoes() -> deveria falhar e passou'];
  exception when others then
    if sqlerrm not ilike '%Acesso restrito%' then
      t := t || array['candidato comum em painel.listar_avaliacoes() -> falhou com outro erro: ' || sqlerrm];
    end if;
  end;

  ---------------------------------------------------------------- painel: cronograma
  perform pg_temp.admin();
  perform pg_temp.como(ustaff, 'staff@teste.local');
  select count(*) into n from painel.listar_cronograma();
  t := t || pg_temp.igual(n::text, '18', 'cronograma tem os 18 itens do Anexo IV');
  select data_fim::text into p from painel.listar_cronograma() where ordem = 12;
  t := t || pg_temp.igual(p, '2026-11-12', 'item 12 (entrevistas) usa a data antecipada do edital atualizado (fim 12/11, não mais 28/11)');
  select data_inicio::text into p from painel.listar_cronograma() where ordem = 18;
  t := t || pg_temp.igual(p, '2026-11-26', 'item 18 (início das convocações) antecipado para 26/11 (era 12/12)');

  ---------------------------------------------------------------- resultado (a exceção desfaz TUDO)
  select count(*), count(x) into v_total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', v_total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
