-- Fase 13 · Publicações da página inicial (migração 20260929180000): documentos e comunicados publicados pela Comissão,
-- cronograma e vagas públicos, ajuste do cronograma com justificativa.
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
-- Uso remoto: colar no SQL Editor do Supabase (ou via MCP execute_sql).
do $teste$
declare
  ustaff constant uuid := 'fd000000-0000-0000-0000-00000000000f';
  ucand constant uuid := 'fd000000-0000-0000-0000-00000000000a';
  pdoc uuid; pcom uuid; prasc uuid;
  caminho constant text := 'teste-fase13/edital.pdf';
  t text[] := '{}';
  n integer; total integer; nf integer;
  p text; b boolean;
begin
  execute $f$create function pg_temp.como(p_uid uuid, p_email text) returns void language plpgsql as $b$
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
      execute 'set local role authenticated';
    end $b$
  $f$;
  execute $f$create function pg_temp.anonimo() returns void language plpgsql as $b$
    begin
      perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
      execute 'set local role anon';
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

  update interno.configuracao set valor = 'false'::jsonb where chave = 'painel_exige_login_seguro';
  insert into auth.users (id, aud, role, email) values
    (ustaff, 'authenticated', 'authenticated', 'staff-pub@teste.local'),
    (ucand, 'authenticated', 'authenticated', 'cand-pub@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email, perfil) values (ustaff, 'Comissão Publicações Teste', 'staff-pub@teste.local', 'comissao');

  -- Comissão envia o PDF ao bucket e cria as publicações
  perform pg_temp.como(ustaff, 'staff-pub@teste.local');
  insert into storage.objects (bucket_id, name) values ('publicacoes', caminho);
  t := t || pg_temp.falha('select painel.salvar_publicacao(null, ''edital'', ''Edital Teste'', null, ''teste-fase13/nao-existe.pdf'', ''x.pdf'', 10)',
                          'publicação com arquivo que não está no bucket', 'arquivo_ausente');
  t := t || pg_temp.falha('select painel.salvar_publicacao(null, ''comunicado'', ''Aviso vazio'', ''  '', null, null, null)',
                          'comunicado sem texto e sem arquivo', 'conteudo_obrigatorio');
  t := t || pg_temp.falha('select painel.salvar_publicacao(null, ''edital'', ''  '', null, null, null, null)', 'sem título', 'titulo_obrigatorio');
  pdoc := painel.salvar_publicacao(null, 'edital', 'Edital Teste nº 001/2026', null, caminho, 'edital.pdf', 12345);
  pcom := painel.salvar_publicacao(null, 'comunicado', 'Comunicado Teste', 'Texto do comunicado de teste.', null, null, null);
  prasc := painel.salvar_publicacao(null, 'comunicado', 'Rascunho Teste', 'Ainda não publicado.', null, null, null);
  select count(*) into n from painel.listar_publicacoes() x where x.titulo like '%Teste%';
  t := t || pg_temp.igual(n::text, '3', 'painel lista as 3 publicações (inclusive não publicadas)');

  -- antes de publicar, o público não vê nada nem baixa o arquivo
  perform pg_temp.anonimo();
  select count(*) into n from publico.listar_publicacoes() x where x.titulo like '%Teste%';
  t := t || pg_temp.igual(n::text, '0', 'nada publicado: público não vê');
  select count(*) into n from storage.objects o where o.bucket_id = 'publicacoes' and o.name = caminho;
  t := t || pg_temp.igual(n::text, '0', 'arquivo não publicado não é legível por anônimo');

  perform pg_temp.como(ustaff, 'staff-pub@teste.local');
  perform painel.publicar_publicacao(pdoc, true);
  perform painel.publicar_publicacao(pcom, true);

  perform pg_temp.anonimo();
  select string_agg(x.titulo || ':' || x.tem_arquivo, ',' order by x.titulo) into p from publico.listar_publicacoes() x where x.titulo like '%Teste%';
  t := t || pg_temp.igual(p, 'Comunicado Teste:false,Edital Teste nº 001/2026:true', 'público vê só as publicadas');
  select count(*) into n from storage.objects o where o.bucket_id = 'publicacoes' and o.name = caminho;
  t := t || pg_temp.igual(n::text, '1', 'arquivo publicado é legível por anônimo');
  select arquivo_path into p from publico.arquivo_da_publicacao(pdoc);
  t := t || pg_temp.igual(p, caminho, 'caminho do arquivo publicado');
  select count(*) into n from publico.arquivo_da_publicacao(prasc);
  t := t || pg_temp.igual(n::text, '0', 'rascunho não entrega arquivo');
  select count(*) into n from publico.cronograma_publico();
  t := t || pg_temp.igual((n > 0)::text, 'true', 'cronograma público');
  select count(*) into n from publico.vagas_publicas();
  t := t || pg_temp.igual(n::text, '9', 'vagas públicas (9 combinações de grupo e nível)');
  t := t || pg_temp.falha('select * from publico.publicacoes', 'anônimo lê a tabela direto', 'permission denied');
  t := t || pg_temp.falha('select * from painel.listar_publicacoes()', 'anônimo lista o painel', 'permission denied');

  -- retirar do ar: some do público; publicar de novo mantém a data original
  perform pg_temp.como(ustaff, 'staff-pub@teste.local');
  select publicado_em::text into p from painel.listar_publicacoes() where id = pdoc;
  perform painel.publicar_publicacao(pdoc, false);
  perform pg_temp.anonimo();
  select count(*) into n from storage.objects o where o.bucket_id = 'publicacoes' and o.name = caminho;
  t := t || pg_temp.igual(n::text, '0', 'retirado do ar: arquivo deixa de ser legível');
  perform pg_temp.como(ustaff, 'staff-pub@teste.local');
  perform painel.publicar_publicacao(pdoc, true);
  t := t || pg_temp.igual((select publicado_em::text from painel.listar_publicacoes() where id = pdoc), p, 'republicar mantém a data da primeira publicação');

  -- edição de título
  perform painel.salvar_publicacao(pcom, 'comunicado', 'Comunicado Teste (corrigido)', 'Texto corrigido.', null, null, null);
  t := t || pg_temp.igual((select titulo from painel.listar_publicacoes() where id = pcom), 'Comunicado Teste (corrigido)', 'edita título');

  -- candidato (logado, não Comissão): não publica nem envia arquivo
  perform pg_temp.como(ucand, 'cand-pub@teste.local');
  t := t || pg_temp.falha('select painel.salvar_publicacao(null, ''comunicado'', ''Invasor'', ''texto'', null, null, null)', 'candidato publica', 'Acesso restrito');
  t := t || pg_temp.falha(format('select painel.publicar_publicacao(%L, false)', pdoc), 'candidato retira do ar', 'Acesso restrito');
  t := t || pg_temp.falha('insert into storage.objects (bucket_id, name) values (''publicacoes'', ''invasor.pdf'')', 'candidato envia PDF', 'row-level security');
  t := t || pg_temp.falha('select painel.salvar_cronograma_item(1, ''X'', null, ''2026-10-05'', null, ''justificativa'')', 'candidato altera cronograma', 'Acesso restrito');

  -- cronograma: Comissão ajusta com justificativa
  perform pg_temp.como(ustaff, 'staff-pub@teste.local');
  t := t || pg_temp.falha('select painel.salvar_cronograma_item(1, ''Publicação do Edital'', null, ''2026-10-06'', null, '''')', 'cronograma sem justificativa', 'justificativa_obrigatoria');
  t := t || pg_temp.falha('select painel.salvar_cronograma_item(3, ''Inscrições'', ''2026-10-20'', ''2026-10-05'', null, ''Retificação teste'')', 'datas invertidas', 'datas_invertidas');
  perform painel.salvar_cronograma_item(1, 'Publicação do Edital', null, '2026-10-06', null, 'Retificação nº 1 (teste)');
  perform pg_temp.anonimo();
  select data_fim::text into p from publico.cronograma_publico() where ordem = 1;
  t := t || pg_temp.igual(p, '2026-10-06', 'público vê o cronograma ajustado');

  -- auditoria
  perform pg_temp.admin();
  select count(*) into n from interno.auditoria where entidade = 'publico.publicacoes' and ator_id = ustaff;
  t := t || pg_temp.igual((n >= 6)::text, 'true', 'publicações auditadas (' || n || ')');
  select count(*) into n from interno.auditoria where entidade = 'interno.cronograma' and ator_id = ustaff;
  t := t || pg_temp.igual(n::text, '2', 'ajuste do cronograma auditado (alteração + justificativa)');

  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
