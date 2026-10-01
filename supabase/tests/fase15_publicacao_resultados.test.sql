-- Fase 15 · Publicação de resultados ao candidato (migração 20261001210000_publicacao_resultado_ac.sql):
-- publico.resultados_candidato (CLAUDE.md seção 6; edital 7.3, 13.2, 13.3) e painel.publicar_resultado_ac,
-- painel.publicar_resultados_ac_lote, painel.publicacoes_ac — cobrem os itens 14 e 17 do Anexo IV
-- (resultado preliminar e definitivo + convocação da análise curricular).
-- Nota: a tabela é lida diretamente pelo candidato (RLS própria linha); por isso a Comissão (sem inscrição
-- própria) NÃO consegue ler publico.resultados_candidato diretamente — só via painel.publicacoes_ac(). As
-- verificações abaixo leem a tabela como administrador (pg_temp.admin) exatamente por isso.
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
-- Uso remoto: colar no SQL Editor do Supabase (ou via MCP execute_sql).
do $teste$
declare
  ustaff constant uuid := 'f5000000-0000-0000-0000-00000000000f';
  ssid constant uuid := gen_random_uuid();
  u_alta constant uuid := 'f5000000-0000-0000-0000-000000000001';
  u_baixa constant uuid := 'f5000000-0000-0000-0000-000000000002';
  i_alta uuid; i_baixa uuid; i_inab uuid;
  t text[] := '{}';
  p text; n integer; total integer; nf integer; qtd integer;
begin
  execute $f$create function pg_temp.como(p_uid uuid, p_email text, p_session uuid) returns void language plpgsql as $b$
    begin
      perform set_config('request.jwt.claims',
        json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email, 'session_id', p_session)::text, true);
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
  -- Candidato (como administrador) habilitado para Grupo A Júnior (Administração, exp. mín. 12 meses), com um
  -- vínculo privado comprovado por CTPS de p_inicio a p_fim; devolve o id da inscrição, já homologada.
  execute $f$create function pg_temp.cand(p_uid uuid, p_n int, p_cpf text, p_inicio date, p_fim date) returns uuid language plpgsql as $b$
    declare v_insc uuid; v_vinc uuid;
    begin
      insert into auth.users (id, aud, role, email) values (p_uid, 'authenticated', 'authenticated', 'pub' || p_n || '@teste.local');
      insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade)
        values (p_uid, 'Publicação Teste ' || p_n, p_cpf, '62999990000', '1985-05-05', 'brasileiro_nato');
      select id into v_insc from publico.inscricoes where candidato_id = (select id from publico.candidatos where user_id = p_uid);
      update publico.inscricoes set grupo = 'A', nivel = 'junior', curso_graduacao = 'Administração',
             grau_graduacao = 'bacharelado', instituicao_graduacao = 'UFG', data_colacao = '2005-12-15', formato_diploma = 'fisico',
             status = 'homologada', submetida_em = now()
        where id = v_insc;
      if p_inicio is not null then
        insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao)
          values (v_insc, 'privado', 'Empresa Teste', 'Analista', p_inicio, p_fim, false, 'Atividades de teste do vínculo')
          returning id into v_vinc;
        insert into publico.documentos (inscricao_id, tipo, vinculo_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
          values (v_insc, 'experiencia_ctps', v_vinc, v_insc || '/experiencia_ctps/' || gen_random_uuid() || '.pdf', 'exp.pdf',
                  md5(v_vinc::text) || md5(p_n::text), 'application/pdf', 1000);
      end if;
      return v_insc;
    end $b$
  $f$;

  insert into auth.users (id, aud, role, email) values (ustaff, 'authenticated', 'authenticated', 'staff-pub@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email) values (ustaff, 'Comissão Publicação Teste', 'staff-pub@teste.local');
  insert into interno.sessoes_painel (session_id, user_id) values (ssid, ustaff);

  -- Alta: 143 meses de vínculo (bem acima dos 12 mínimos) -> experiência no teto de 35,0 -> AC >= 35.
  i_alta := pg_temp.cand(u_alta, 1, '11144477735', '2010-01-01', '2021-12-01');
  -- Baixa: exatamente 12 meses (= o mínimo, sem excedente) -> habilitado, AC = 0 (abaixo de 35).
  i_baixa := pg_temp.cand(u_baixa, 2, '52998224725', '2020-01-01', '2021-01-01');
  -- Inabilitado: sem nenhum vínculo declarado -> experiência insuficiente.
  i_inab := pg_temp.cand('f5000000-0000-0000-0000-000000000003', 3, '39053344705', null, null);

  perform pg_temp.como(ustaff, 'staff-pub@teste.local', ssid);

  ---------------------------------------------------------------- validações
  t := t || pg_temp.falha(format('select painel.publicar_resultado_ac(%L, ''etapa_invalida'', ''justificativa de teste'')', i_alta),
    'etapa inválida', 'etapa_invalida');
  t := t || pg_temp.falha(format('select painel.publicar_resultado_ac(%L, ''ac_preliminar'', ''oi'')', i_alta),
    'justificativa curta', 'justificativa_obrigatoria');
  t := t || pg_temp.falha('select painel.publicar_resultado_ac(gen_random_uuid(), ''ac_preliminar'', ''justificativa de teste'')',
    'inscrição inexistente');

  ---------------------------------------------------------------- publicações (preliminar, definitivo, republicação)
  perform painel.publicar_resultado_ac(i_alta, 'ac_preliminar', 'Resultado preliminar da AC (Anexo IV, item 14).');
  perform painel.publicar_resultado_ac(i_baixa, 'ac_preliminar', 'Resultado preliminar da AC (Anexo IV, item 14).');
  perform painel.publicar_resultado_ac(i_inab, 'ac_preliminar', 'Resultado preliminar da AC (Anexo IV, item 14).');
  perform painel.publicar_resultado_ac(i_alta, 'ac_definitivo', 'Resultado definitivo + convocação (Anexo IV, item 17).');
  perform painel.publicar_resultado_ac(i_baixa, 'ac_definitivo', 'Resultado definitivo + convocação (Anexo IV, item 17).');
  perform painel.publicar_resultado_ac(i_baixa, 'ac_preliminar', 'Republicação após julgamento de recurso.');

  ---------------------------------------------------------------- homologação é pré-requisito
  perform pg_temp.admin();
  update publico.inscricoes set status = 'submetida' where id = i_inab;
  perform pg_temp.como(ustaff, 'staff-pub@teste.local', ssid);
  t := t || pg_temp.falha(format('select painel.publicar_resultado_ac(%L, ''ac_preliminar'', ''justificativa de teste'')', i_inab),
    'publicar sem homologação', 'nao_homologada');
  perform pg_temp.admin();
  update publico.inscricoes set status = 'homologada' where id = i_inab;
  perform pg_temp.como(ustaff, 'staff-pub@teste.local', ssid);

  ---------------------------------------------------------------- lote (inclui as 3 de teste; pode incluir outras já homologadas de A/júnior)
  select painel.publicar_resultados_ac_lote('ac_preliminar', 'A', 'junior', 'Publicação em lote (Anexo IV, item 14).') into qtd;
  t := t || pg_temp.igual((qtd >= 3)::text, 'true', 'lote publica ao menos as 3 inscrições homologadas de teste de A/júnior');

  ---------------------------------------------------------------- visão da Comissão (via função, não a tabela direto)
  select count(*)::text into p from painel.publicacoes_ac() where inscricao_id in (i_alta, i_baixa, i_inab);
  t := t || pg_temp.igual(p, '5', 'painel vê as 5 publicações (alta: preliminar+definitivo; baixa: preliminar+definitivo; inab: preliminar)');

  ---------------------------------------------------------------- conteúdo publicado (lido como administrador, bypassa a RLS "própria linha")
  perform pg_temp.admin();
  select situacao || '|' || coalesce(posicao::text, '-') into p from publico.resultados_candidato where inscricao_id = i_alta and etapa = 'ac_preliminar';
  t := t || pg_temp.igual(p, 'habilitado|1', 'alta: habilitado, 1º lugar (AC >= 35)');
  select (pontuacao >= 35)::text into p from publico.resultados_candidato where inscricao_id = i_alta and etapa = 'ac_preliminar';
  t := t || pg_temp.igual(p, 'true', 'alta: pontuação publicada >= 35');

  select situacao || '|' || coalesce(posicao::text, '-') into p from publico.resultados_candidato where inscricao_id = i_baixa and etapa = 'ac_preliminar';
  t := t || pg_temp.igual(p, 'habilitado|-', 'baixa: habilitado, sem posição (AC abaixo de 35)');

  select situacao into p from publico.resultados_candidato where inscricao_id = i_inab and etapa = 'ac_preliminar';
  t := t || pg_temp.igual(p, 'inabilitado', 'inabilitado: situação publicada');
  select (motivacao is not null and char_length(motivacao) > 0)::text into p
    from publico.resultados_candidato where inscricao_id = i_inab and etapa = 'ac_preliminar';
  t := t || pg_temp.igual(p, 'true', 'inabilitado: motivação publicada (não vazia)');

  select situacao into p from publico.resultados_candidato where inscricao_id = i_alta and etapa = 'ac_definitivo';
  t := t || pg_temp.igual(p, 'convocado para a entrevista técnica', 'alta: convocado no resultado definitivo (1 vaga x 3 = até 3º lugar)');

  select situacao into p from publico.resultados_candidato where inscricao_id = i_baixa and etapa = 'ac_definitivo';
  t := t || pg_temp.igual(p, 'habilitado, não convocado para a entrevista técnica', 'baixa: habilitado mas não convocado (abaixo de 35 pts)');

  select count(*)::text into p from publico.resultados_candidato where inscricao_id = i_baixa and etapa = 'ac_preliminar';
  t := t || pg_temp.igual(p, '1', 'republicar a mesma etapa atualiza a linha, não duplica');

  ---------------------------------------------------------------- acesso: o candidato só vê o próprio resultado
  perform pg_temp.como(u_alta, 'pub1@teste.local', gen_random_uuid());
  select count(*)::text into p from publico.resultados_candidato;
  t := t || pg_temp.igual(p, '2', 'candidato alta vê só as próprias publicações (preliminar + definitivo)');
  select situacao into p from publico.resultados_candidato where etapa = 'ac_definitivo';
  t := t || pg_temp.igual(p, 'convocado para a entrevista técnica', 'candidato alta vê a própria situação definitiva');
  t := t || pg_temp.falha(format('select painel.publicar_resultado_ac(%L, ''ac_preliminar'', ''justificativa de teste'')', i_baixa),
    'candidato publica resultado', 'Acesso restrito');
  t := t || pg_temp.falha('select * from painel.publicacoes_ac()', 'candidato lê a visão da Comissão', 'Acesso restrito');

  perform pg_temp.como(u_baixa, 'pub2@teste.local', gen_random_uuid());
  select string_agg(distinct inscricao_id::text, ',') into p from publico.resultados_candidato;
  t := t || pg_temp.igual(p, i_baixa::text, 'candidato baixa só vê as próprias publicações, nunca as do candidato alta');

  ---------------------------------------------------------------- auditoria (só as nossas 3 inscrições de teste, imune a dados antigos de A/júnior)
  perform pg_temp.admin();
  select count(*) into n from interno.auditoria
    where entidade = 'publico.resultados_candidato' and ator_id = ustaff and entidade_id in (i_alta::text, i_baixa::text, i_inab::text);
  t := t || pg_temp.igual(n::text, '9', 'cada publicação (inclusive a republicação e o lote) fica na auditoria, por inscrição (3+4+2)');

  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
