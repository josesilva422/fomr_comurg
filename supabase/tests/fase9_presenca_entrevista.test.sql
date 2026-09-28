-- Fase 9 · Presença na entrevista técnica (edital 6.5.7; migração 20260928100000).
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
do $teste$
declare
  ustaff constant uuid := 'f7000000-0000-0000-0000-00000000000f';
  sstaff constant uuid := 'f8000000-0000-0000-0000-00000000000f';
  ua constant uuid := 'f7000000-0000-0000-0000-00000000000a';  -- convocado, entrevista realizada
  ub constant uuid := 'f7000000-0000-0000-0000-00000000000b';  -- convocado, não compareceu
  uc constant uuid := 'f7000000-0000-0000-0000-00000000000c';  -- convocado, já com ficha
  ud constant uuid := 'f7000000-0000-0000-0000-00000000000d';  -- abaixo de 35 (não convocado)
  ia uuid; ib uuid; ic uuid; id_ uuid;
  t text[] := '{}';
  n integer; total integer; nf integer;
  p text;
begin
  execute $f$create function pg_temp.como(p_uid uuid, p_email text) returns void language plpgsql as $b$
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email,
        'session_id', case when p_uid = 'f7000000-0000-0000-0000-00000000000f' then 'f8000000-0000-0000-0000-00000000000f' end)::text, true);
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
  -- candidato Grupo A / Júnior com um vínculo (p_inicio a p_fim); envia a inscrição
  execute $f$create function pg_temp.cria_candidato(p_uid uuid, p_email text, p_nome text, p_cpf text, p_inicio date, p_fim date)
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
        values (v_insc, 'privado', 'Empresa Teste', 'Analista', p_inicio, p_fim, false, 'Atividades de teste do vínculo')
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
    (ustaff, 'authenticated', 'authenticated', 'staff-pres@teste.local'),
    (ua, 'authenticated', 'authenticated', 'pres-a@teste.local'),
    (ub, 'authenticated', 'authenticated', 'pres-b@teste.local'),
    (uc, 'authenticated', 'authenticated', 'pres-c@teste.local'),
    (ud, 'authenticated', 'authenticated', 'pres-d@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email) values (ustaff, 'Comissão Presença Teste', 'staff-pres@teste.local');
  insert into interno.sessoes_painel (session_id, user_id) values (sstaff, ustaff);

  ia := pg_temp.cria_candidato(ua, 'pres-a@teste.local', 'Presenca A Realizada', '12345678143', '2015-01-01', '2026-01-01');
  ib := pg_temp.cria_candidato(ub, 'pres-b@teste.local', 'Presenca B Ausente', '23456789254', '2015-01-01', '2026-01-01');
  ic := pg_temp.cria_candidato(uc, 'pres-c@teste.local', 'Presenca C Com Ficha', '34567890337', '2015-01-01', '2026-01-01');
  id_ := pg_temp.cria_candidato(ud, 'pres-d@teste.local', 'Presenca D Abaixo', '45678901400', '2025-01-01', '2026-01-01');
  perform pg_temp.admin();
  -- ficha de um avaliador fictício para o candidato C
  insert into interno.fichas_entrevista (inscricao_id, avaliador_id, avaliador_nome, nota_dominio, nota_analise, nota_planejamento, nota_comunicacao, nota_caso, nota_postura,
    just_dominio, just_analise, just_planejamento, just_comunicacao, just_caso, just_postura)
    values (ic, gen_random_uuid(), 'Avaliador Fictício Teste', 8, 8, 4, 4, 4, 4, 'teste ok', 'teste ok', 'teste ok', 'teste ok', 'teste ok', 'teste ok');

  ---------------------------------------------------------------- regras de quem pode e quando
  perform pg_temp.como(ua, 'pres-a@teste.local');
  t := t || pg_temp.falha(format('select painel.registrar_presenca_entrevista(%L, ''realizada'')', ia), 'candidato registra a própria presença', 'restrito');
  t := t || pg_temp.falha('select * from interno.presenca_entrevista', 'candidato lê a tabela de presença', 'permission denied');
  select count(*) into n from publico.minha_presenca_entrevista();
  t := t || pg_temp.igual(n::text, '0', 'sem registro, o candidato não vê situação de entrevista');

  perform pg_temp.como(ustaff, 'staff-pres@teste.local');
  t := t || pg_temp.falha(format('select painel.registrar_presenca_entrevista(%L, ''realizada'')', ia), 'presença sem convite registrado', 'sem_convite');
  t := t || pg_temp.falha(format('select painel.registrar_presenca_entrevista(%L, ''realizada'')', id_), 'presença de candidato não convocado', 'nao_convocado');
  t := t || pg_temp.falha(format('select painel.registrar_presenca_entrevista(%L, ''talvez'')', ia), 'situação inválida', 'situacao_invalida');

  perform painel.registrar_convite_entrevista(ia, 'Entrevista Técnica Estruturada', current_date + 5, '10:00', 'https://meet.teste/a', null);
  perform painel.registrar_convite_entrevista(ib, 'Entrevista Técnica Estruturada', current_date + 5, '11:00', 'https://meet.teste/b', null);
  perform painel.registrar_convite_entrevista(ic, 'Entrevista Técnica Estruturada', current_date + 5, '12:00', 'https://meet.teste/c', null);

  ---------------------------------------------------------------- A: entrevista realizada
  select (painel.registrar_presenca_entrevista(ia, 'realizada', null)).situacao into p;
  t := t || pg_temp.igual(p, 'realizada', 'Comissão registra entrevista realizada');
  perform pg_temp.como(ua, 'pres-a@teste.local');
  select situacao into p from publico.minha_presenca_entrevista();
  t := t || pg_temp.igual(p, 'realizada', 'candidato A vê "realizada" (em avaliação pela banca)');

  ---------------------------------------------------------------- B: não compareceu (eliminado, item 6.5.7)
  perform pg_temp.como(ustaff, 'staff-pres@teste.local');
  select (painel.registrar_presenca_entrevista(ib, 'nao_compareceu', 'Não entrou na sala em 15 minutos.')).situacao into p;
  t := t || pg_temp.igual(p, 'nao_compareceu', 'Comissão registra não comparecimento');
  perform pg_temp.como(ub, 'pres-b@teste.local');
  select situacao into p from publico.minha_presenca_entrevista();
  t := t || pg_temp.igual(p, 'nao_compareceu', 'candidato B vê "não compareceu"');
  perform pg_temp.como(ustaff, 'staff-pres@teste.local');
  t := t || pg_temp.falha(format('select painel.salvar_ficha_entrevista(%L, ''{"dominio":8,"analise":8,"planejamento":4,"comunicacao":4,"caso":4,"postura":4}''::jsonb, ''{"dominio":"ok ok","analise":"ok ok","planejamento":"ok ok","comunicacao":"ok ok","caso":"ok ok","postura":"ok ok"}''::jsonb)', ib),
    'ficha para quem foi eliminado por ausência', 'eliminado_ausencia');

  ---------------------------------------------------------------- C: já tem ficha, não pode ser dado como ausente
  t := t || pg_temp.falha(format('select painel.registrar_presenca_entrevista(%L, ''nao_compareceu'')', ic), 'ausência para quem já tem ficha', 'ja_tem_ficha');

  ---------------------------------------------------------------- correção e histórico
  perform painel.registrar_presenca_entrevista(ib, 'realizada', 'Corrigido: o candidato havia entrado com atraso.');
  select situacao into p from painel.presenca_entrevista_do_candidato(ib) limit 1;
  t := t || pg_temp.igual(p, 'realizada', 'correção: a mais recente vale');
  select count(*) into n from painel.presenca_entrevista_do_candidato(ib);
  t := t || pg_temp.igual(n::text, '2', 'o histórico guarda os dois registros');
  perform pg_temp.como(ub, 'pres-b@teste.local');
  select situacao into p from publico.minha_presenca_entrevista();
  t := t || pg_temp.igual(p, 'realizada', 'candidato B passa a ver "realizada" após a correção');

  perform pg_temp.admin();
  select count(*) into n from interno.auditoria where entidade = 'interno.presenca_entrevista' and ator_id = ustaff;
  t := t || pg_temp.igual(n::text, '3', 'os três registros ficam na auditoria com o autor');

  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
