-- Fase 20 · Fila de revisão da Comissão com IA (migração 20261002120000_fila_revisao_documentos.sql):
-- painel.listar_fila_revisao (documento ao lado da última extração, entre candidatos) e
-- painel.revisar_extracao (marca revisada/corrigida; não é uma decisão do processo, só o registro de
-- que um humano confrontou o documento com a extração — CLAUDE.md seção 2).
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
-- Uso remoto: colar no SQL Editor do Supabase (ou via MCP execute_sql).
do $teste$
declare
  ustaff constant uuid := 'fa000000-0000-0000-0000-00000000000f';
  ssid constant uuid := gen_random_uuid();
  ua constant uuid := 'fa000000-0000-0000-0000-000000000001'; -- sem extração
  ub constant uuid := 'fa000000-0000-0000-0000-000000000002'; -- extração pendente, sem indícios
  uc constant uuid := 'fa000000-0000-0000-0000-000000000003'; -- extração pendente, com suspeita de adulteração
  ud constant uuid := 'fa000000-0000-0000-0000-000000000004'; -- extração já revisada
  d_a uuid; d_b uuid; d_c uuid; d_d uuid;
  e_b uuid; e_c uuid; e_d uuid;
  t text[] := '{}';
  p text; n integer; total integer; nf integer;
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
  -- Candidato (admin) com um documento de identidade; devolve o id do documento.
  execute $f$create function pg_temp.cand_doc(p_uid uuid, p_n int, p_cpf text) returns uuid language plpgsql as $b$
    declare v_insc uuid; v_doc uuid;
    begin
      insert into auth.users (id, aud, role, email) values (p_uid, 'authenticated', 'authenticated', 'fila' || p_n || '@teste.local');
      insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade)
        values (p_uid, 'Fila Teste ' || p_n, p_cpf, '62999990000', '1985-05-05', 'brasileiro_nato');
      select id into v_insc from publico.inscricoes where candidato_id = (select id from publico.candidatos where user_id = p_uid);
      update publico.inscricoes set status = 'submetida', submetida_em = now() where id = v_insc;
      insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes)
        values (v_insc, 'identidade', v_insc || '/identidade/' || gen_random_uuid() || '.pdf', 'rg.pdf',
                md5(v_insc::text) || md5('rg' || p_n), 'application/pdf', 1000)
        returning id into v_doc;
      return v_doc;
    end $b$
  $f$;

  insert into auth.users (id, aud, role, email) values (ustaff, 'authenticated', 'authenticated', 'staff-fila@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email) values (ustaff, 'Comissão Fila Teste', 'staff-fila@teste.local');
  insert into interno.sessoes_painel (session_id, user_id) values (ssid, ustaff);

  d_a := pg_temp.cand_doc(ua, 1, '11144477735');
  d_b := pg_temp.cand_doc(ub, 2, '52998224725');
  d_c := pg_temp.cand_doc(uc, 3, '39053344705');
  d_d := pg_temp.cand_doc(ud, 4, '22233344316');

  insert into interno.extracoes (documento_id, modelo, versao_prompt, json_extraido, confianca) values
    (d_b, 'gpt-4o', 'v1', '{"legivel": true, "resumo_documento": "RG legível", "tipo_documento": {"bate_com_esperado": true},
       "indicios_adulteracao": {"suspeita": false}, "comparacoes": [{"campo": "nome", "confere": "sim"}]}'::jsonb, 0.95)
    returning id into e_b;
  insert into interno.extracoes (documento_id, modelo, versao_prompt, json_extraido, confianca) values
    (d_c, 'gpt-4o', 'v1', '{"legivel": true, "resumo_documento": "RG com indício de adulteração", "tipo_documento": {"bate_com_esperado": true},
       "indicios_adulteracao": {"suspeita": true, "detalhes": "Fonte inconsistente no número do RG"},
       "comparacoes": [{"campo": "nome", "confere": "nao"}]}'::jsonb, 0.4)
    returning id into e_c;
  insert into interno.extracoes (documento_id, modelo, versao_prompt, json_extraido, confianca, status) values
    (d_d, 'gpt-4o', 'v1', '{"legivel": true, "resumo_documento": "RG já revisado", "tipo_documento": {"bate_com_esperado": true},
       "indicios_adulteracao": {"suspeita": false}, "comparacoes": []}'::jsonb, 0.9, 'revisada')
    returning id into e_d;

  perform pg_temp.como(ustaff, 'staff-fila@teste.local', ssid);

  ---------------------------------------------------------------- fila "pendente" (padrão): sem_extracao + pendente, não a já revisada
  select string_agg(nome, ',' order by nome) into p from painel.listar_fila_revisao() where documento_id in (d_a, d_b, d_c, d_d);
  t := t || pg_temp.igual(p, 'Fila Teste 1,Fila Teste 2,Fila Teste 3', 'fila pendente traz sem_extracao + pendentes, não a já revisada');

  select status into p from painel.listar_fila_revisao() where documento_id = d_a;
  t := t || pg_temp.igual(p, 'sem_extracao', 'documento nunca extraído aparece como sem_extracao');

  -- a com suspeita de adulteração vem antes da sem indício, dentro dos nossos documentos de teste
  -- (ordenação geral: indício de adulteração primeiro, depois confiança crescente)
  select (array_agg(nome order by confianca nulls first))[1] into p
    from painel.listar_fila_revisao() where documento_id in (d_b, d_c);
  t := t || pg_temp.igual(p, 'Fila Teste 3', 'entre os nossos, o de suspeita de adulteração tem a menor confiança (vem antes na fila)');

  select suspeita_adulteracao::text into p from painel.listar_fila_revisao() where documento_id = d_c;
  t := t || pg_temp.igual(p, 'true', 'sinaliza a suspeita de adulteração');
  select qtd_nao_confere::text into p from painel.listar_fila_revisao() where documento_id = d_c;
  t := t || pg_temp.igual(p, '1', 'conta os campos que não conferem');

  -- fila "todas" inclui a já revisada; "revisada" só ela
  select count(*)::text into p from painel.listar_fila_revisao('todas') where documento_id in (d_a, d_b, d_c, d_d);
  t := t || pg_temp.igual(p, '4', 'fila "todas" traz os 4 documentos');
  select string_agg(nome, ',') into p from painel.listar_fila_revisao('revisada') where documento_id in (d_a, d_b, d_c, d_d);
  t := t || pg_temp.igual(p, 'Fila Teste 4', 'fila "revisada" só traz a já revisada');

  ---------------------------------------------------------------- validações e marcação
  t := t || pg_temp.falha(format('select painel.revisar_extracao(%L, ''status_invalido'', null)', e_b), 'status inválido', 'status_invalido');
  t := t || pg_temp.falha('select painel.revisar_extracao(gen_random_uuid(), ''revisada'', null)', 'extração inexistente', 'nao_encontrada');

  perform painel.revisar_extracao(e_b, 'revisada', 'Confere com o documento original.');
  select status into p from painel.listar_fila_revisao('revisada') where documento_id = d_b;
  t := t || pg_temp.igual(p, 'revisada', 'marcar como revisada atualiza o status');

  perform painel.revisar_extracao(e_c, 'corrigida', 'A IA leu "nome" errado; o documento confere ao comparar manualmente.');
  select status into p from painel.listar_fila_revisao('corrigida') where documento_id = d_c;
  t := t || pg_temp.igual(p, 'corrigida', 'marcar como corrigida com observação');

  -- depois de revisadas/corrigidas, saem da fila "pendente"
  select count(*)::text into p from painel.listar_fila_revisao('pendente') where documento_id in (d_b, d_c);
  t := t || pg_temp.igual(p, '0', 'revisadas/corrigidas saem da fila pendente');

  ---------------------------------------------------------------- acesso
  perform pg_temp.como(ua, 'fila1@teste.local', gen_random_uuid());
  t := t || pg_temp.falha('select * from painel.listar_fila_revisao()', 'candidato lê a fila', 'Acesso restrito');
  t := t || pg_temp.falha(format('select painel.revisar_extracao(%L, ''revisada'', null)', e_b), 'candidato revisa extração', 'Acesso restrito');
  t := t || pg_temp.falha('select * from interno.extracoes', 'candidato lê a tabela direto', 'permission denied');

  ---------------------------------------------------------------- auditoria
  perform pg_temp.admin();
  select count(*) into n from interno.auditoria where entidade = 'interno.extracoes' and ator_id = ustaff and entidade_id in (e_b::text, e_c::text);
  t := t || pg_temp.igual(n::text, '2', 'as duas revisões ficam na auditoria');

  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
