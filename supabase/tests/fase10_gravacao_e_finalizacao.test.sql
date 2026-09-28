-- Fase 10 · Link da gravação (interno) e finalização do registro do candidato (migração 20260928110000).
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
do $teste$
declare
  ustaff constant uuid := 'f9000000-0000-0000-0000-00000000000f';
  sstaff constant uuid := 'fa000000-0000-0000-0000-00000000000f';
  ua constant uuid := 'f9000000-0000-0000-0000-00000000000a';
  ub constant uuid := 'f9000000-0000-0000-0000-00000000000b';
  ia uuid; ib uuid;
  t text[] := '{}';
  total integer; nf integer; n integer;
  p text; b boolean; k int;
begin
  execute $f$create function pg_temp.como(p_uid uuid, p_email text) returns void language plpgsql as $b$
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email,
        'session_id', case when p_uid = 'f9000000-0000-0000-0000-00000000000f' then 'fa000000-0000-0000-0000-00000000000f' end)::text, true);
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
        values (v_insc, 'privado', 'Empresa Teste', 'Analista', '2015-01-01', '2026-01-01', false, 'Atividades de teste do vínculo')
        returning id into v_vinc;
      insert into publico.documentos (inscricao_id, tipo, vinculo_id, storage_path, nome_original, sha256, mime, tamanho_bytes) values
        (v_insc, 'identidade', null, v_insc || '/identidade/' || gen_random_uuid() || '.pdf', 'rg.pdf', repeat('a', 64), 'application/pdf', 1000),
        (v_insc, 'diploma_graduacao', null, v_insc || '/diploma_graduacao/' || gen_random_uuid() || '.pdf', 'diploma.pdf', repeat('b', 64), 'application/pdf', 1000),
        (v_insc, 'experiencia_ctps', v_vinc, v_insc || '/experiencia_ctps/' || gen_random_uuid() || '.pdf', 'ctps.pdf', repeat('c', 64), 'application/pdf', 1000),
        (v_insc, 'comprovante_pix', null, v_insc || '/comprovante_pix/' || gen_random_uuid() || '.png', 'pix.png', repeat('d', 64), 'image/png', 1000);
      perform publico.aceitar_declaracoes();
      perform publico.submeter_inscricao();
      return v_insc;
    end $b$
  $f$;

  update interno.configuracao set valor = to_jsonb((now() - interval '1 day')::text) where chave = 'inscricoes_abertura';
  update interno.configuracao set valor = to_jsonb((now() + interval '7 days')::text) where chave = 'inscricoes_encerramento';
  insert into auth.users (id, aud, role, email) values
    (ustaff, 'authenticated', 'authenticated', 'staff-fin@teste.local'),
    (ua, 'authenticated', 'authenticated', 'fin-a@teste.local'),
    (ub, 'authenticated', 'authenticated', 'fin-b@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email) values (ustaff, 'Comissão Final Teste', 'staff-fin@teste.local');
  insert into interno.sessoes_painel (session_id, user_id) values (sstaff, ustaff);

  ia := pg_temp.cria_candidato(ua, 'fin-a@teste.local', 'Final A Compareceu', '12345678143');
  ib := pg_temp.cria_candidato(ub, 'fin-b@teste.local', 'Final B Ausente', '23456789254');
  perform pg_temp.como(ustaff, 'staff-fin@teste.local');
  perform painel.registrar_convite_entrevista(ia, 'Entrevista Técnica Estruturada', current_date + 5, '10:00', 'https://meet.teste/a', null);
  perform painel.registrar_convite_entrevista(ib, 'Entrevista Técnica Estruturada', current_date + 5, '11:00', 'https://meet.teste/b', null);

  t := t || pg_temp.falha(format('select painel.registrar_presenca_entrevista(%L, ''realizada'', null, ''ftp://gravacao'')', ia), 'link de gravação inválido', 'link_invalido');
  t := t || pg_temp.falha(format('select painel.finalizar_entrevista(%L)', ia), 'finalizar sem registrar presença', 'sem_presenca');
  select link_gravacao into p from painel.registrar_presenca_entrevista(ia, 'realizada', 'Tudo certo com a reunião.', 'https://teams.teste/gravacao/123');
  t := t || pg_temp.igual(p, 'https://teams.teste/gravacao/123', 'registra presença com observação e link da gravação');
  select link_gravacao into p from painel.presenca_entrevista_do_candidato(ia) limit 1;
  t := t || pg_temp.igual(p, 'https://teams.teste/gravacao/123', 'o painel enxerga o link da gravação');

  perform pg_temp.como(ua, 'fin-a@teste.local');
  select situacao into p from publico.minha_presenca_entrevista();
  t := t || pg_temp.igual(p, 'realizada', 'candidato vê só a situação');
  select finalizada into b from publico.minha_presenca_entrevista();
  t := t || pg_temp.igual(b::text, 'false', 'antes de finalizar, finalizada = false');
  t := t || pg_temp.falha('select link_gravacao from publico.minha_presenca_entrevista()', 'candidato lê o link da gravação', 'link_gravacao');
  t := t || pg_temp.falha('select observacao from publico.minha_presenca_entrevista()', 'candidato lê a observação', 'observacao');
  t := t || pg_temp.falha(format('select painel.finalizar_entrevista(%L)', ia), 'candidato finaliza o próprio registro', 'restrito');

  perform pg_temp.como(ustaff, 'staff-fin@teste.local');
  t := t || pg_temp.falha(format('select painel.finalizar_entrevista(%L)', ia), 'finalizar sem 3 fichas', 'faltam_fichas');
  perform pg_temp.admin();
  for k in 1..2 loop
    insert into interno.fichas_entrevista (inscricao_id, avaliador_id, avaliador_nome, nota_dominio, nota_analise, nota_planejamento, nota_comunicacao, nota_caso, nota_postura,
      just_dominio, just_analise, just_planejamento, just_comunicacao, just_caso, just_postura)
      values (ia, gen_random_uuid(), 'Avaliador Fictício ' || k, 8, 8, 4, 4, 4, 4, 'teste ok', 'teste ok', 'teste ok', 'teste ok', 'teste ok', 'teste ok');
  end loop;
  perform pg_temp.como(ustaff, 'staff-fin@teste.local');
  t := t || pg_temp.falha(format('select painel.finalizar_entrevista(%L)', ia), 'finalizar com só 2 fichas', 'faltam_fichas');
  perform pg_temp.admin();
  insert into interno.fichas_entrevista (inscricao_id, avaliador_id, avaliador_nome, nota_dominio, nota_analise, nota_planejamento, nota_comunicacao, nota_caso, nota_postura,
    just_dominio, just_analise, just_planejamento, just_comunicacao, just_caso, just_postura)
    values (ia, gen_random_uuid(), 'Avaliador Fictício 3', 8, 8, 4, 4, 4, 4, 'teste ok', 'teste ok', 'teste ok', 'teste ok', 'teste ok', 'teste ok');

  perform pg_temp.como(ustaff, 'staff-fin@teste.local');
  select (painel.finalizar_entrevista(ia)).finalizado_por::text into p;
  t := t || pg_temp.igual(p, ustaff::text, 'finaliza com 3 fichas e presença registrada (autor gravado)');
  select count(*) into n from painel.entrevista_finalizacao(ia);
  t := t || pg_temp.igual(n::text, '1', 'painel mostra quem finalizou e quando');
  t := t || pg_temp.falha(format('select painel.finalizar_entrevista(%L)', ia), 'finalizar duas vezes', 'entrevista_finalizada');
  t := t || pg_temp.falha(format('select painel.registrar_presenca_entrevista(%L, ''nao_compareceu'')', ia), 'registrar presença depois de finalizado', 'entrevista_finalizada');
  t := t || pg_temp.falha(format('select painel.salvar_ficha_entrevista(%L, ''{"dominio":8,"analise":8,"planejamento":4,"comunicacao":4,"caso":4,"postura":4}''::jsonb, ''{"dominio":"ok ok","analise":"ok ok","planejamento":"ok ok","comunicacao":"ok ok","caso":"ok ok","postura":"ok ok"}''::jsonb)', ia), 'lançar ficha depois de finalizado', 'entrevista_finalizada');
  t := t || pg_temp.falha(format('select painel.remover_minha_ficha(%L, ''motivo qualquer'')', ia), 'remover ficha depois de finalizado', 'entrevista_finalizada');

  perform pg_temp.como(ua, 'fin-a@teste.local');
  select finalizada into b from publico.minha_presenca_entrevista();
  t := t || pg_temp.igual(b::text, 'true', 'candidato vê que a avaliação técnica foi finalizada');

  perform pg_temp.como(ustaff, 'staff-fin@teste.local');
  perform painel.registrar_presenca_entrevista(ib, 'nao_compareceu', 'Não entrou na sala.', 'https://teams.teste/gravacao/456');
  t := t || pg_temp.falha(format('select painel.finalizar_entrevista(%L)', ib), 'finalizar candidato que não compareceu', 'sem_presenca');

  perform pg_temp.admin();
  select count(*) into n from interno.auditoria where entidade = 'interno.entrevista_finalizada' and ator_id = ustaff;
  t := t || pg_temp.igual(n::text, '1', 'a finalização fica na auditoria com o autor');

  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
