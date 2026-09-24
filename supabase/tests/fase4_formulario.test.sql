-- Aba "Formulário" do painel e relatório por candidato (migração 20260924100000_formulario_da_inscricao.sql).
-- Roda inteiro dentro de UMA transação desfeita no final. Uso remoto: colar no SQL Editor / MCP execute_sql.
do $teste$
declare
  ustaff constant uuid := 'd0000000-0000-0000-0000-00000000000d';
  ua constant uuid := 'e0000000-0000-0000-0000-00000000000a';
  t text[] := '{}'; n integer; v_total integer; nf integer; p text; ia uuid; v_vinc uuid; v_tit uuid;
begin
  execute $f$create function pg_temp.como(p_uid uuid, p_email text) returns void language plpgsql as $b$
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
      execute 'set local role authenticated';
    end $b$ $f$;
  execute $f$create function pg_temp.igual(p_atual text, p_esperado text, p_rotulo text) returns text language plpgsql as $b$
    begin
      if p_atual is not distinct from p_esperado then return null; end if;
      return p_rotulo || ' -> esperado [' || coalesce(p_esperado, 'NULL') || '] obtido [' || coalesce(p_atual, 'NULL') || ']';
    end $b$ $f$;
  update interno.configuracao set valor = to_jsonb((now() - interval '1 day')::text) where chave = 'inscricoes_abertura';
  update interno.configuracao set valor = to_jsonb((now() + interval '7 days')::text) where chave = 'inscricoes_encerramento';
  insert into auth.users (id, aud, role, email) values (ustaff, 'authenticated', 'authenticated', 'staff@teste.local'), (ua, 'authenticated', 'authenticated', 'ea@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email, perfil) values (ustaff, 'Fiscal Teste', 'staff@teste.local', 'comissao');

  perform pg_temp.como(ua, 'ea@teste.local');
  insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade) values (ua, 'Formulario Teste Silva', '12345678143', '62999990000', '1988-03-14', 'brasileiro_nato');
  select id into ia from publico.inscricoes;
  update publico.inscricoes set grupo = 'A', nivel = 'junior', curso_graduacao = 'Administração', grau_graduacao = 'bacharelado',
         instituicao_graduacao = 'UFG', data_colacao = '2010-12-15', formato_diploma = 'fisico' where id = ia;
  insert into publico.vinculos_declarados (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao)
    values (ia, 'privado', 'Empresa Teste', 'Analista', '2015-01-01', '2026-01-01', false, 'Atividades de teste do vínculo') returning id into v_vinc;
  insert into publico.titulos_declarados (inscricao_id, tipo, denominacao, instituicao, carga_horaria, data_conclusao)
    values (ia, 'especializacao', 'Pós 1', 'FGV', 400, '2020-01-01') returning id into v_tit;
  insert into publico.documentos (inscricao_id, tipo, vinculo_id, storage_path, nome_original, sha256, mime, tamanho_bytes) values
    (ia, 'identidade', null, ia || '/identidade/' || gen_random_uuid() || '.pdf', 'rg.pdf', repeat('a', 64), 'application/pdf', 1000),
    (ia, 'diploma_graduacao', null, ia || '/diploma_graduacao/' || gen_random_uuid() || '.pdf', 'diploma.pdf', repeat('b', 64), 'application/pdf', 1000),
    (ia, 'experiencia_ctps', v_vinc, ia || '/experiencia_ctps/' || gen_random_uuid() || '.pdf', 'ctps.pdf', repeat('c', 64), 'application/pdf', 1000),
    (ia, 'comprovante_pix', null, ia || '/comprovante_pix/' || gen_random_uuid() || '.png', 'pix.png', repeat('d', 64), 'image/png', 1000);
  insert into publico.documentos (inscricao_id, tipo, titulo_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
    values (ia, 'diploma_pos', v_tit, ia || '/diploma_pos/' || gen_random_uuid() || '.pdf', 'pos.pdf', repeat('1', 64), 'application/pdf', 1000);
  perform publico.aceitar_declaracoes();
  perform publico.submeter_inscricao();

  perform pg_temp.como(ustaff, 'staff@teste.local');
  select count(*) into n from painel.relatorio_respostas('A', 'junior', null) r where r ->> 'nome' = 'Formulario Teste Silva';
  t := t || pg_temp.igual(n::text, '1', 'relatório por grupo/nível continua achando o candidato após a refatoração');
  select r ->> 'nome' into p from painel.relatorio_respostas(null, null, '123.456.781-43') r;
  t := t || pg_temp.igual(p, 'Formulario Teste Silva', 'relatório filtrado por CPF (usado pelo botão por candidato)');
  select jsonb_array_length(painel.formulario_da_inscricao(ia) -> 'titulos')::text into p;
  t := t || pg_temp.igual(p, '1', 'formulario_da_inscricao traz os títulos');
  select painel.formulario_da_inscricao(ia) ->> 'nome' into p;
  t := t || pg_temp.igual(p, 'Formulario Teste Silva', 'formulario_da_inscricao traz o nome');
  select jsonb_array_length(painel.formulario_da_inscricao(ia) -> 'documentos')::text into p;
  t := t || pg_temp.igual(p, '5', 'formulario_da_inscricao lista os 5 documentos');

  perform pg_temp.como(ua, 'ea@teste.local');
  begin
    perform painel.formulario_da_inscricao(ia);
    t := t || array['candidato comum leu o formulário pelo painel -> deveria falhar e passou'];
  exception when others then
    if sqlerrm not ilike '%Acesso restrito%' then t := t || array['erro inesperado: ' || sqlerrm]; end if;
  end;

  select count(*), count(x) into v_total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', v_total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
