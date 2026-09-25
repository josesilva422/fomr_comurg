-- Fase 12 · Convite para a entrevista técnica (migração 20260925170000): só candidatos convocados (6.5.1) recebem
-- convite; campos validados; histórico e resultado do envio do e-mail; o candidato vê só o próprio convite, o mais recente.
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
-- Uso remoto: colar no SQL Editor do Supabase (ou via MCP execute_sql).
do $teste$
declare
  ustaff constant uuid := 'fc000000-0000-0000-0000-00000000000f';
  ua constant uuid := 'fc000000-0000-0000-0000-00000000000a';  -- convocado
  un constant uuid := 'fc000000-0000-0000-0000-00000000000b';  -- habilitado, mas abaixo de 35 pontos
  ia uuid; in_ uuid; cid uuid;
  amanha constant date := (now() at time zone 'America/Sao_Paulo')::date + 1;
  t text[] := '{}';
  n integer; total integer; nf integer;
  p text; j jsonb;
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
  execute $f$create function pg_temp.falha(p_sql text, p_rotulo text, p_trecho text) returns text language plpgsql as $b$
    declare v_hint text;
    begin
      execute p_sql;
      return p_rotulo || ' -> deveria falhar e passou';
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint;
      if sqlerrm ilike ('%' || p_trecho || '%') or coalesce(v_hint, '') ilike ('%' || p_trecho || '%') then return null; end if;
      return p_rotulo || ' -> falhou com outro erro: ' || sqlerrm;
    end $b$
  $f$;
  -- candidato do Grupo C / Júnior com um vínculo comprovado e n especializações (cada uma 2 pts)
  execute $f$create function pg_temp.cria_candidato(p_uid uuid, p_email text, p_nome text, p_cpf text, p_inicio date, p_fim date, p_n_esp int)
    returns uuid language plpgsql as $b$
    declare v_insc uuid; v_vinc uuid; v_tit uuid; i int;
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
      execute 'set local role authenticated';
      insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade)
        values (p_uid, p_nome, p_cpf, '62999990000', '1988-03-14', 'brasileiro_nato');
      select id into v_insc from publico.inscricoes where candidato_id = (select id from publico.candidatos where user_id = p_uid);
      update publico.inscricoes set grupo = 'C', nivel = 'junior', curso_graduacao = 'Administração',
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
      for i in 1..p_n_esp loop
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

  update interno.configuracao set valor = to_jsonb((now() - interval '1 day')::text) where chave = 'inscricoes_abertura';
  update interno.configuracao set valor = to_jsonb((now() + interval '7 days')::text) where chave = 'inscricoes_encerramento';
  update interno.configuracao set valor = 'false'::jsonb where chave = 'painel_exige_login_seguro';
  insert into auth.users (id, aud, role, email) values
    (ustaff, 'authenticated', 'authenticated', 'staff-conv@teste.local'),
    (ua, 'authenticated', 'authenticated', 'conv-a@teste.local'), (un, 'authenticated', 'authenticated', 'conv-n@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email, perfil) values (ustaff, 'Comissão Convite Teste', 'staff-conv@teste.local', 'comissao');

  ia := pg_temp.cria_candidato(ua, 'conv-a@teste.local', 'Ana Convite Teste', '52998224725', '2015-01-01', '2026-01-01', 5);   -- AC 45
  in_ := pg_temp.cria_candidato(un, 'conv-n@teste.local', 'Nei Convite Teste', '39053344705', '2024-01-01', '2025-12-01', 0);  -- AC 15

  perform pg_temp.como(ustaff, 'staff-conv@teste.local');
  -- só convocados
  t := t || pg_temp.falha(format('select painel.registrar_convite_entrevista(%L, ''Entrevista'', %L, ''14:00'', ''https://meet.google.com/abc'', null)', in_, amanha),
                          'convite para não convocado', 'nao_convocado');
  -- validações
  t := t || pg_temp.falha(format('select painel.registrar_convite_entrevista(%L, ''  '', %L, ''14:00'', ''https://meet.google.com/abc'', null)', ia, amanha),
                          'sem título', 'titulo_obrigatorio');
  t := t || pg_temp.falha(format('select painel.registrar_convite_entrevista(%L, ''Entrevista'', null, ''14:00'', ''https://meet.google.com/abc'', null)', ia),
                          'sem data', 'data_obrigatoria');
  t := t || pg_temp.falha(format('select painel.registrar_convite_entrevista(%L, ''Entrevista'', %L, ''14:00'', ''https://meet.google.com/abc'', null)', ia, amanha - 2),
                          'data passada', 'data_passada');
  t := t || pg_temp.falha(format('select painel.registrar_convite_entrevista(%L, ''Entrevista'', %L, ''14:00'', ''http://meet.google.com/abc'', null)', ia, amanha),
                          'link sem https', 'link_invalido');
  t := t || pg_temp.falha(format('select painel.registrar_convite_entrevista(%L, ''Entrevista'', %L, ''14:00'', ''javascript:alert(1)'', null)', ia, amanha),
                          'link javascript:', 'link_invalido');

  -- convite válido: devolve os dados do e-mail
  j := painel.registrar_convite_entrevista(ia, 'Entrevista Técnica', amanha, '14:30', 'https://meet.google.com/abc-defg-hij', '  Entrar 10 min antes.  ');
  cid := (j ->> 'id')::uuid;
  t := t || pg_temp.igual(j ->> 'email', 'conv-a@teste.local', 'e-mail do candidato');
  t := t || pg_temp.igual(j ->> 'nome', 'Ana Convite Teste', 'nome do candidato');
  t := t || pg_temp.igual(j ->> 'horario', '14:30', 'horário HH:MI');
  t := t || pg_temp.igual(j ->> 'grupo' || '/' || (j ->> 'nivel'), 'C/junior', 'grupo e nível');
  t := t || pg_temp.igual(j ->> 'orientacoes', 'Entrar 10 min antes.', 'orientações sem espaços nas pontas');
  t := t || pg_temp.igual(j ->> 'enviado_por', 'Comissão Convite Teste', 'quem enviou');
  perform painel.marcar_convite_enviado(cid, false, 'SMTP não configurado no servidor');
  select email_enviado::text || '|' || email_erro into p from painel.convites_entrevista_do_candidato(ia);
  t := t || pg_temp.igual(p, 'false|SMTP não configurado no servidor', 'registra falha do envio');

  -- reenvio: novo convite substitui o anterior; histórico mantido
  j := painel.registrar_convite_entrevista(ia, 'Entrevista Técnica (remarcada)', amanha + 1, '09:00', 'https://teams.microsoft.com/l/x', null);
  perform painel.marcar_convite_enviado((j ->> 'id')::uuid, true, null);
  select count(*) into n from painel.convites_entrevista_do_candidato(ia);
  t := t || pg_temp.igual(n::text, '2', 'histórico com 2 convites');
  select titulo || '|' || email_enviado::text into p from painel.convites_entrevista_do_candidato(ia) limit 1;
  t := t || pg_temp.igual(p, 'Entrevista Técnica (remarcada)|true', 'o mais recente vem primeiro');
  select horario || '|' || email_enviado::text into p from painel.convites_entrevista_resumo() where inscricao_id = ia;
  t := t || pg_temp.igual(p, '09:00|true', 'resumo da lista mostra o último convite');
  select count(*) into n from painel.convites_entrevista_resumo() where inscricao_id = in_;
  t := t || pg_temp.igual(n::text, '0', 'sem convite, fora do resumo');

  -- candidato: vê só o próprio, o mais recente
  perform pg_temp.como(ua, 'conv-a@teste.local');
  select titulo || '|' || data::text || '|' || horario into p from publico.meu_convite_entrevista();
  t := t || pg_temp.igual(p, 'Entrevista Técnica (remarcada)|' || (amanha + 1)::text || '|09:00', 'candidato vê o convite vigente');
  perform pg_temp.como(un, 'conv-n@teste.local');
  select count(*) into n from publico.meu_convite_entrevista();
  t := t || pg_temp.igual(n::text, '0', 'outro candidato não vê convite');

  -- acesso
  t := t || pg_temp.falha(format('select painel.registrar_convite_entrevista(%L, ''X Teste'', %L, ''14:00'', ''https://a.b/c'', null)', ia, amanha),
                          'candidato cria convite', 'Acesso restrito');
  t := t || pg_temp.falha(format('select * from painel.convites_entrevista_do_candidato(%L)', ia), 'candidato lê histórico', 'Acesso restrito');
  t := t || pg_temp.falha('select * from painel.convites_entrevista_resumo()', 'candidato lê resumo', 'Acesso restrito');
  t := t || pg_temp.falha(format('select painel.marcar_convite_enviado(%L, true, null)', cid), 'candidato marca envio', 'Acesso restrito');
  t := t || pg_temp.falha('select * from interno.convites_entrevista', 'candidato lê a tabela', 'permission denied');

  -- auditoria
  perform pg_temp.admin();
  select count(*) into n from interno.auditoria where entidade = 'interno.convites_entrevista' and ator_id = ustaff;
  t := t || pg_temp.igual((n >= 2)::text, 'true', 'convites na auditoria com o autor (' || n || ')');

  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
