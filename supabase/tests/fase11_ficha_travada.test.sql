-- Fase 11 · Ficha travada no envio e perfil do avaliador (migração 20260928130000).
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
do $teste$
declare
  ustaff constant uuid := 'fb000000-0000-0000-0000-00000000000f';
  sstaff constant uuid := 'fc000000-0000-0000-0000-00000000000f';
  ua constant uuid := 'fb000000-0000-0000-0000-00000000000a';
  ia uuid;
  t text[] := '{}';
  total integer; nf integer; n integer;
  p text;
  notas constant text := '{"dominio":8,"analise":8,"planejamento":4,"comunicacao":4,"caso":4,"postura":4}';
  justs constant text := '{"dominio":"ok ok","analise":"ok ok","planejamento":"ok ok","comunicacao":"ok ok","caso":"ok ok","postura":"ok ok"}';
begin
  execute $f$create function pg_temp.como(p_uid uuid, p_email text) returns void language plpgsql as $b$
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email,
        'session_id', case when p_uid = 'fb000000-0000-0000-0000-00000000000f' then 'fc000000-0000-0000-0000-00000000000f' end)::text, true);
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
    (ustaff, 'authenticated', 'authenticated', 'aval-fic@teste.local'),
    (ua, 'authenticated', 'authenticated', 'cand-fic@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email, cpf) values (ustaff, 'Maria Avaliadora Teste', 'aval-fic@teste.local', '52998224725');
  insert into interno.sessoes_painel (session_id, user_id) values (sstaff, ustaff);
  ia := pg_temp.cria_candidato(ua, 'cand-fic@teste.local', 'Ficha A Candidato', '12345678143');

  perform pg_temp.como(ustaff, 'aval-fic@teste.local');
  select nome into p from painel.meu_perfil();
  t := t || pg_temp.igual(p, 'Maria Avaliadora Teste', 'o perfil traz o nome do cadastro (sem digitar)');
  select cpf_mascarado into p from painel.meu_perfil();
  t := t || pg_temp.igual(p, '***.***.***-25', 'o CPF sai mascarado');
  perform pg_temp.como(ua, 'cand-fic@teste.local');
  t := t || pg_temp.falha('select * from painel.meu_perfil()', 'candidato lê o perfil do painel', 'restrito');

  perform pg_temp.como(ustaff, 'aval-fic@teste.local');
  select (painel.salvar_ficha_entrevista(ia, notas::jsonb, justs::jsonb) ->> 'avaliador_nome') into p;
  t := t || pg_temp.igual(p, 'Maria Avaliadora Teste', 'a ficha grava o nome do cadastro do avaliador');
  t := t || pg_temp.falha(format('select painel.salvar_ficha_entrevista(%L, %L::jsonb, %L::jsonb)', ia, notas, justs), 'reenviar/alterar ficha já enviada', 'ficha_ja_enviada');
  perform painel.remover_minha_ficha(ia, 'Erro de digitação na nota.');
  select (painel.salvar_ficha_entrevista(ia, notas::jsonb, justs::jsonb) ->> 'avaliador_nome') into p;
  t := t || pg_temp.igual(p, 'Maria Avaliadora Teste', 'depois de remover com motivo, dá para lançar de novo');

  perform pg_temp.admin();
  select count(*) into n from interno.auditoria where acao = 'MOTIVO_REMOCAO_FICHA' and ator_id = ustaff;
  t := t || pg_temp.igual(n::text, '1', 'a remoção com motivo fica na auditoria');

  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
