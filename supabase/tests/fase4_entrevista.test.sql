-- Fase 4 · Testes da entrevista técnica e da classificação PF = AC + ET com desempate (migrações
-- 20260923110000_entrevista_tecnica_e_classificacao.sql e 20260925130000_entrevista_fichas_por_avaliador.sql):
-- cada avaliador (login próprio) lança só a SUA ficha; ninguém vê a nota de outro; média (ET) e PF só com 3+ fichas;
-- no máximo 10 fichas por candidato.
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
-- Uso remoto: colar no SQL Editor do Supabase (ou via MCP execute_sql).
do $teste$
declare
  ustaff constant uuid := 'd0000000-0000-0000-0000-00000000000d';
  -- avaliadores: X, Y, Z (+ 8 extras para o limite de 10)
  ux constant uuid := 'd1000000-0000-0000-0000-000000000001';
  uy constant uuid := 'd1000000-0000-0000-0000-000000000002';
  uz constant uuid := 'd1000000-0000-0000-0000-000000000003';
  k integer; r jsonb;
  ua constant uuid := 'e0000000-0000-0000-0000-00000000000a';
  ub constant uuid := 'e0000000-0000-0000-0000-00000000000b';
  uc constant uuid := 'e0000000-0000-0000-0000-00000000000c';
  ud constant uuid := 'e0000000-0000-0000-0000-00000000000d';
  ue constant uuid := 'e0000000-0000-0000-0000-00000000000e';
  ia uuid; ib uuid; ic uuid; id_ uuid; ie uuid; fid uuid;
  t text[] := '{}';
  n integer; v_total integer; nf integer;
  p text;
  j constant jsonb := '{"dominio":"adequado","analise":"adequado","planejamento":"adequado","comunicacao":"adequado","caso":"adequado","postura":"adequado"}';
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
  -- tenta uma operação que DEVE falhar e devolve null se falhou com a mensagem esperada
  execute $f$create function pg_temp.deve_falhar(p_sql text, p_rotulo text, p_trecho text) returns text language plpgsql as $b$
    begin
      execute p_sql;
      return p_rotulo || ' -> deveria falhar e passou';
    exception when others then
      if sqlerrm ilike '%' || p_trecho || '%' then return null; end if;
      return p_rotulo || ' -> falhou com outro erro: ' || sqlerrm;
    end $b$
  $f$;
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

  update interno.configuracao set valor = to_jsonb((now() - interval '1 day')::text) where chave = 'inscricoes_abertura';
  update interno.configuracao set valor = to_jsonb((now() + interval '7 days')::text) where chave = 'inscricoes_encerramento';
  -- em produção o painel exige sessão validada por código; dentro desta transação (desfeita no fim) a exigência é desligada
  update interno.configuracao set valor = 'false'::jsonb where chave = 'painel_exige_login_seguro';
  insert into auth.users (id, aud, role, email) values
    (ustaff, 'authenticated', 'authenticated', 'staff@teste.local'),
    (ux, 'authenticated', 'authenticated', 'x@teste.local'), (uy, 'authenticated', 'authenticated', 'y@teste.local'),
    (uz, 'authenticated', 'authenticated', 'z@teste.local'),
    (ua, 'authenticated', 'authenticated', 'ea@teste.local'), (ub, 'authenticated', 'authenticated', 'eb@teste.local'),
    (uc, 'authenticated', 'authenticated', 'ec@teste.local'), (ud, 'authenticated', 'authenticated', 'ed@teste.local'),
    (ue, 'authenticated', 'authenticated', 'ee@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email, perfil) values
    (ustaff, 'Fiscal Teste', 'staff@teste.local', 'comissao'),
    (ux, 'Avaliador X', 'x@teste.local', 'comissao'), (uy, 'Avaliador Y', 'y@teste.local', 'comissao'),
    (uz, 'Avaliador Z', 'z@teste.local', 'comissao');
  -- 8 avaliadores extras (para o limite de 10 fichas)
  for k in 1..8 loop
    insert into auth.users (id, aud, role, email) values (('d2000000-0000-0000-0000-' || lpad(k::text, 12, '0'))::uuid, 'authenticated', 'authenticated', 'extra' || k || '@teste.local');
    insert into interno.usuarios_internos (user_id, nome, email, perfil) values (('d2000000-0000-0000-0000-' || lpad(k::text, 12, '0'))::uuid, 'Avaliador Extra ' || k, 'extra' || k || '@teste.local', 'comissao');
  end loop;

  -- Grupo A / Júnior (vagas 1 => corte 3, mas empate no 3º inclui os dois). ACs: A=45, B=41, C=37, D=37, E=35 (5º, fora)
  ia := pg_temp.cria_candidato(ua, 'ea@teste.local', 'Entrevista A', '12345678143', '2015-01-01', '2026-01-01', 5);
  ib := pg_temp.cria_candidato(ub, 'eb@teste.local', 'Entrevista B', '23456789254', '2015-01-01', '2026-01-01', 3);
  ic := pg_temp.cria_candidato(uc, 'ec@teste.local', 'Entrevista C', '34567890337', '2015-01-01', '2026-01-01', 1);
  id_ := pg_temp.cria_candidato(ud, 'ed@teste.local', 'Entrevista D', '45678901400', '2015-01-01', '2026-01-01', 1);
  ie := pg_temp.cria_candidato(ue, 'ee@teste.local', 'Entrevista E', '56789012575', '2015-01-01', '2026-01-01', 0);

  perform pg_temp.como(ux, 'x@teste.local');

  -- validações
  t := t || pg_temp.deve_falhar(format($q$select painel.salvar_ficha_entrevista(%L, '{"dominio":5,"analise":5,"planejamento":3,"comunicacao":3,"caso":2,"postura":2}', %L)$q$, ie, j::text),
                                'ficha para candidato NÃO convocado', 'convocados');
  t := t || pg_temp.deve_falhar(format($q$select painel.salvar_ficha_entrevista(%L, '{"dominio":11,"analise":5,"planejamento":3,"comunicacao":3,"caso":2,"postura":2}', %L)$q$, ia, j::text),
                                'nota acima do peso (domínio 11)', 'inválida');
  t := t || pg_temp.deve_falhar(format($q$select painel.salvar_ficha_entrevista(%L, '{"dominio":5,"analise":5,"planejamento":6,"comunicacao":3,"caso":2,"postura":2}', %L)$q$, ia, j::text),
                                'nota acima do peso (planejamento 6, peso 5)', 'inválida');
  t := t || pg_temp.deve_falhar(format($q$select painel.salvar_ficha_entrevista(%L, '{"dominio":5,"analise":5,"planejamento":3,"comunicacao":3,"caso":2,"postura":2}', '{"dominio":"ok"}')$q$, ia),
                                'justificativa ausente', 'Justificativa obrigatória');

  -- CEGUEIRA: X lança a ficha de A; Y não vê a nota de X, nem média
  perform painel.salvar_ficha_entrevista(ia, '{"dominio":5,"analise":5,"planejamento":3,"comunicacao":3,"caso":2,"postura":2}', j);
  r := painel.entrevista_do_candidato(ia);
  t := t || pg_temp.igual(r #>> '{minha_ficha,total}', '20', 'X vê a própria ficha (total 20)');
  t := t || pg_temp.igual(r ->> 'et', null, 'com 1 ficha não há média (ET)');
  perform pg_temp.como(uy, 'y@teste.local');
  r := painel.entrevista_do_candidato(ia);
  t := t || pg_temp.igual(r ->> 'minha_ficha', null, 'Y não tem ficha e não recebe a de X');
  t := t || pg_temp.igual(r ->> 'n_fichas', '1', 'Y vê que há 1 ficha enviada');
  t := t || pg_temp.igual((r::text like '%"total"%')::text, 'false', 'Y não recebe nenhum total de ficha (só contagem e nomes)');
  t := t || pg_temp.igual(r #>> '{avaliadores,0,nome}', 'Avaliador X', 'Y vê QUEM já enviou (sem nota)');
  perform painel.salvar_ficha_entrevista(ia, '{"dominio":5,"analise":5,"planejamento":3,"comunicacao":3,"caso":2,"postura":2}', j);
  r := painel.entrevista_do_candidato(ia);
  t := t || pg_temp.igual(r ->> 'et', null, 'com 2 fichas ainda não há média');
  t := t || pg_temp.igual(r ->> 'media_por_competencia', null, 'com 2 fichas não há média por competência');
  select count(*)::text into p from painel.classificacao_final('A', 'junior') x where x ->> 'nome' = 'Entrevista A' and x ->> 'et' is null and x ->> 'pf' is null;
  t := t || pg_temp.igual(p, '1', 'classificação também esconde ET/PF com 2 fichas');
  perform pg_temp.como(uz, 'z@teste.local');
  perform painel.salvar_ficha_entrevista(ia, '{"dominio":5,"analise":5,"planejamento":3,"comunicacao":3,"caso":2,"postura":2}', j);
  r := painel.entrevista_do_candidato(ia);
  t := t || pg_temp.igual(r ->> 'et', '20.00', 'com 3 fichas aparece a média (ET 20)');
  t := t || pg_temp.igual(r #>> '{media_por_competencia,dominio}', '5.00', 'com 3 fichas aparece a média por competência');
  t := t || pg_temp.igual(r ->> 'pf', '65.00', 'PF de A = AC 45 + ET 20');
  t := t || pg_temp.igual((r::text like '%"just_dominio"%')::text, 'true', 'Z recebe só a própria ficha com justificativas');
  t := t || pg_temp.igual(jsonb_array_length(r -> 'avaliadores')::text, '3', 'lista de quem enviou tem 3 nomes');

  -- B: 3 avaliadores, todos total 24  => ET 24  => PF 41+24 = 65  (EMPATE de PF com A; desempate II: maior ET => B primeiro)
  perform pg_temp.como(ux, 'x@teste.local');
  perform painel.salvar_ficha_entrevista(ib, '{"dominio":6,"analise":6,"planejamento":3,"comunicacao":3,"caso":3,"postura":3}', j);
  perform pg_temp.como(uy, 'y@teste.local');
  perform painel.salvar_ficha_entrevista(ib, '{"dominio":6,"analise":6,"planejamento":3,"comunicacao":3,"caso":3,"postura":3}', j);
  perform pg_temp.como(uz, 'z@teste.local');
  perform painel.salvar_ficha_entrevista(ib, '{"dominio":6,"analise":6,"planejamento":3,"comunicacao":3,"caso":3,"postura":3}', j);
  -- C: 3 avaliadores, total 12 => ET 12 (< 15: abaixo do corte)
  perform pg_temp.como(ux, 'x@teste.local');
  perform painel.salvar_ficha_entrevista(ic, '{"dominio":3,"analise":3,"planejamento":2,"comunicacao":2,"caso":1,"postura":1}', j);
  perform pg_temp.como(uy, 'y@teste.local');
  perform painel.salvar_ficha_entrevista(ic, '{"dominio":3,"analise":3,"planejamento":2,"comunicacao":2,"caso":1,"postura":1}', j);
  perform pg_temp.como(uz, 'z@teste.local');
  perform painel.salvar_ficha_entrevista(ic, '{"dominio":3,"analise":3,"planejamento":2,"comunicacao":2,"caso":1,"postura":1}', j);
  -- D: 1 ficha só (sem média)
  perform painel.salvar_ficha_entrevista(id_, '{"dominio":9,"analise":9,"planejamento":5,"comunicacao":5,"caso":5,"postura":5}', j);

  select string_agg((x ->> 'nome') || ':' || coalesce(x ->> 'pf', 'null') || ':' || coalesce(x ->> 'posicao', 'null') || ':' || (x ->> 'abaixo_do_corte') || ':' || (x ->> 'banca_completa'), ' | ' order by x ->> 'nome')
    into p
    from painel.classificacao_final('A', 'junior') x where x ->> 'nome' like 'Entrevista %';
  t := t || pg_temp.igual(p,
    'Entrevista A:65.00:2:false:true | Entrevista B:65.00:1:false:true | Entrevista C:49.00:null:true:true | Entrevista D:null:null:false:false',
    'classificação: PF empatado (65) desempata pela maior ET (B antes de A); C abaixo do corte sem posição; D com 1 ficha sem média; E fora — obtido: ' || coalesce(p, 'nenhuma'));

  select (painel.entrevista_do_candidato(ie)) ->> 'convocado' into p;
  t := t || pg_temp.igual(p, 'false', 'E aparece como não convocado');

  -- página do avaliador
  select string_agg(x.nome || ':' || coalesce(x.minha_ficha_total::text, '-') || ':' || x.n_fichas || ':' || x.media_liberada, ' | ' order by x.nome)
    into p from painel.minhas_entrevistas() x where x.nome like 'Entrevista %';
  t := t || pg_temp.igual(p, 'Entrevista A:20:3:true | Entrevista B:24:3:true | Entrevista C:12:3:true | Entrevista D:38:1:false',
    'Minhas fichas (Z): convocados com a própria nota e a situação da banca');

  -- correção: o próprio avaliador regrava a ficha (upsert) -> ET muda
  perform pg_temp.como(ux, 'x@teste.local');
  perform painel.salvar_ficha_entrevista(ia, '{"dominio":8,"analise":5,"planejamento":3,"comunicacao":3,"caso":2,"postura":2}', j);
  select (painel.entrevista_do_candidato(ia)) ->> 'et' into p;
  t := t || pg_temp.igual(p, '21.00', 'corrigir a própria ficha atualiza a média ((23+20+20)/3)');
  select (painel.entrevista_do_candidato(ia)) ->> 'n_fichas' into p;
  t := t || pg_temp.igual(p, '3', 'a correção não duplica a ficha do avaliador');

  -- remoção: só a própria, exige motivo; com 2 fichas a média some de novo
  t := t || pg_temp.deve_falhar(format($q$select painel.remover_minha_ficha(%L, '')$q$, ia), 'remover ficha sem motivo', 'motivo');
  t := t || pg_temp.deve_falhar(format($q$select painel.remover_minha_ficha(%L, 'Não avaliei este')$q$, ie), 'remover ficha que não existe', 'não tem ficha');
  perform painel.remover_minha_ficha(ia, 'Lançada no candidato errado');
  r := painel.entrevista_do_candidato(ia);
  t := t || pg_temp.igual(r ->> 'et', null, 'com 2 fichas (após remoção) a média volta a ficar oculta');
  t := t || pg_temp.igual(r ->> 'minha_ficha', null, 'a ficha removida era a de X');

  -- limite de 10 fichas: D já tem 1 (Z); + X, Y e 7 extras = 10; o 8º extra é recusado
  perform pg_temp.como(ux, 'x@teste.local');
  perform painel.salvar_ficha_entrevista(id_, '{"dominio":5,"analise":5,"planejamento":3,"comunicacao":3,"caso":2,"postura":2}', j);
  perform pg_temp.como(uy, 'y@teste.local');
  perform painel.salvar_ficha_entrevista(id_, '{"dominio":5,"analise":5,"planejamento":3,"comunicacao":3,"caso":2,"postura":2}', j);
  for k in 1..7 loop
    perform pg_temp.como(('d2000000-0000-0000-0000-' || lpad(k::text, 12, '0'))::uuid, 'extra' || k || '@teste.local');
    perform painel.salvar_ficha_entrevista(id_, '{"dominio":5,"analise":5,"planejamento":3,"comunicacao":3,"caso":2,"postura":2}', j);
  end loop;
  select (painel.entrevista_do_candidato(id_)) ->> 'n_fichas' into p;
  t := t || pg_temp.igual(p, '10', 'D chega a 10 fichas');
  perform pg_temp.como('d2000000-0000-0000-0000-000000000008'::uuid, 'extra8@teste.local');
  t := t || pg_temp.deve_falhar(format($q$select painel.salvar_ficha_entrevista(%L, '{"dominio":5,"analise":5,"planejamento":3,"comunicacao":3,"caso":2,"postura":2}', %L)$q$, id_, j::text),
                                'a 11ª ficha é recusada', '10 fichas');
  perform pg_temp.como(uy, 'y@teste.local');
  perform painel.salvar_ficha_entrevista(id_, '{"dominio":6,"analise":5,"planejamento":3,"comunicacao":3,"caso":2,"postura":2}', j);
  select (painel.entrevista_do_candidato(id_)) ->> 'n_fichas' into p;
  t := t || pg_temp.igual(p, '10', 'no limite, quem já tem ficha ainda pode corrigir a sua');

  -- Usuários do painel não mostram mais o total de cada ficha
  select (count(*) > 0 and bool_and(x.avaliados::text not like '%"total"%'))::text into p
    from painel.listar_usuarios_painel() x where x.qtd_fichas > 0;
  t := t || pg_temp.igual(p, 'true', 'Usuários do painel: fichas listadas sem o total (nota individual)');

  -- só a Comissão
  perform pg_temp.como(ua, 'ea@teste.local');
  t := t || pg_temp.deve_falhar(format($q$select painel.entrevista_do_candidato(%L)$q$, ia), 'candidato comum lê a entrevista', 'Acesso restrito');
  t := t || pg_temp.deve_falhar(format($q$select painel.salvar_ficha_entrevista(%L, '{"dominio":5,"analise":5,"planejamento":3,"comunicacao":3,"caso":2,"postura":2}', %L)$q$, ia, j::text), 'candidato comum lança ficha', 'Acesso restrito');
  t := t || pg_temp.deve_falhar('select * from painel.minhas_entrevistas()', 'candidato comum lê Minhas fichas', 'Acesso restrito');
  t := t || pg_temp.deve_falhar('select * from interno.fichas_entrevista', 'candidato lê a tabela de fichas', 'permission denied');
  t := t || pg_temp.deve_falhar('select * from painel.classificacao_final()', 'candidato comum lê a classificação', 'Acesso restrito');
  perform pg_temp.como(ux, 'x@teste.local');
  t := t || pg_temp.deve_falhar('select * from interno.fichas_entrevista', 'membro da Comissão lê a tabela de fichas direto', 'permission denied');

  -- auditoria
  perform pg_temp.admin();
  select count(*) into n from interno.auditoria where entidade = 'interno.fichas_entrevista' and acao = 'INSERT';
  t := t || pg_temp.igual(n::text, '19', 'cada ficha lançada fica na auditoria (19 inserções)');
  select count(*) into n from interno.auditoria where entidade = 'interno.fichas_entrevista' and acao = 'UPDATE';
  t := t || pg_temp.igual(n::text, '2', 'as correções ficam na auditoria');
  select count(*) into n from interno.auditoria where acao = 'MOTIVO_REMOCAO_FICHA';
  t := t || pg_temp.igual(n::text, '1', 'o motivo da remoção fica na auditoria');

  select count(*), count(x) into v_total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', v_total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
