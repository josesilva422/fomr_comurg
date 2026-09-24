-- Fase 5 · Isenção da taxa: regras de pendência (hipótese, NIS, prazo) e decisão da Comissão
-- (edital 4.10 e 4.10.1, Anexo IV item 4; decreto municipal, art. 4º; migrações 20260924130000 e 20260924140000).
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
do $teste$
declare
  ustaff constant uuid := 'f0000000-0000-0000-0000-00000000000f';
  ua constant uuid := 'f1000000-0000-0000-0000-00000000000a';
  ub constant uuid := 'f1000000-0000-0000-0000-00000000000b';
  ia uuid; ib uuid;
  t text[] := '{}';
  n integer; total integer; nf integer;
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
  execute $f$create function pg_temp.falha(p_sql text, p_rotulo text, p_trecho text default null) returns text language plpgsql as $b$
    declare v_msg text; v_hint text;
    begin
      execute p_sql;
      return p_rotulo || ' -> deveria falhar e passou';
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint;
      v_msg := sqlerrm;
      if p_trecho is not null and (v_msg not ilike ('%' || p_trecho || '%')) and (coalesce(v_hint, '') not ilike ('%' || p_trecho || '%')) then
        return p_rotulo || ' -> falhou com outro erro: ' || v_msg;
      end if;
      return null;
    end $b$
  $f$;
  execute $f$create function pg_temp.igual(p_atual text, p_esperado text, p_rotulo text) returns text language plpgsql as $b$
    begin
      if p_atual is not distinct from p_esperado then return null; end if;
      return p_rotulo || ' -> esperado [' || coalesce(p_esperado, 'NULL') || '] obtido [' || coalesce(p_atual, 'NULL') || ']';
    end $b$
  $f$;

  ---------------------------------------------------------------- preparo
  update interno.configuracao set valor = to_jsonb((now() - interval '1 day')::text) where chave = 'inscricoes_abertura';
  update interno.configuracao set valor = to_jsonb((now() + interval '7 days')::text) where chave = 'inscricoes_encerramento';
  insert into auth.users (id, aud, role, email) values
    (ustaff, 'authenticated', 'authenticated', 'staff-isencao@teste.local'),
    (ua, 'authenticated', 'authenticated', 'isenc-a@teste.local'),
    (ub, 'authenticated', 'authenticated', 'isenc-b@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email) values (ustaff, 'Comissão Teste', 'staff-isencao@teste.local');

  perform pg_temp.como(ua, 'isenc-a@teste.local');
  insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade)
    values (ua, 'Ana Isencao Teste', '52998224725', '62999990000', '1988-03-14', 'brasileiro_nato');
  select id into ia from publico.inscricoes;
  perform pg_temp.como(ub, 'isenc-b@teste.local');
  insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade)
    values (ub, 'Bia Isencao Teste', '39053344705', '62988880000', '1990-05-20', 'brasileiro_nato');
  select id into ib from publico.inscricoes;

  ---------------------------------------------------------------- pendências do pedido (candidata A)
  perform pg_temp.como(ua, 'isenc-a@teste.local');
  update publico.inscricoes set solicitou_isencao = true where id = ia;
  select string_agg(codigo, ',') into p from publico.verificar_inscricao();
  t := t || pg_temp.igual((p like '%isencao_incompleta%')::text, 'true', 'pedido sem hipótese é incompleto');
  update publico.inscricoes set hipotese_isencao = 'cadunico' where id = ia;
  insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes)
    values (ia, 'requerimento_isencao', ia || '/requerimento_isencao/' || gen_random_uuid() || '.pdf', 'decl.pdf', repeat('a', 64), 'application/pdf', 1000);
  select string_agg(codigo, ',') into p from publico.verificar_inscricao();
  t := t || pg_temp.igual((p like '%isencao_incompleta%')::text, 'true', 'baixa renda sem NIS é incompleto (mesmo com documento)');
  update publico.inscricoes set nis_isencao = '12345678901' where id = ia;
  select string_agg(codigo, ',') into p from publico.verificar_inscricao();
  t := t || pg_temp.igual((coalesce(p, '') like '%isencao_incompleta%')::text, 'false', 'baixa renda com NIS e documento não tem pendência de isenção');
  t := t || pg_temp.igual((coalesce(p, '') like '%isencao_fora_do_prazo%')::text, 'false', 'dentro do prazo do pedido');

  perform pg_temp.admin();
  update interno.configuracao set valor = to_jsonb((now() - interval '1 minute')::text) where chave = 'isencao_pedidos_fim';
  perform pg_temp.como(ua, 'isenc-a@teste.local');
  select string_agg(codigo, ',') into p from publico.verificar_inscricao();
  t := t || pg_temp.igual((p like '%isencao_fora_do_prazo%')::text, 'true', 'pedido de isenção depois de 06/10 é barrado');
  perform pg_temp.admin();
  update interno.configuracao set valor = to_jsonb('2026-10-06T23:59:59-03:00'::text) where chave = 'isencao_pedidos_fim';

  ---------------------------------------------------------------- decisão da Comissão
  -- simula pedidos já enviados (status aguardando_isencao) sem passar pelo fluxo completo do formulário
  update publico.inscricoes set status = 'aguardando_isencao', solicitou_isencao = true where id in (ia, ib);
  update publico.inscricoes set hipotese_isencao = 'doador_sangue' where id = ib;

  perform pg_temp.como(ua, 'isenc-a@teste.local');
  t := t || pg_temp.falha('select * from painel.listar_isencoes()', 'candidato lista isenções', 'restrito');
  t := t || pg_temp.falha(format('select painel.decidir_isencao(%L, ''deferida'', ''motivo com mais de dez caracteres'')', ia), 'candidato decide a própria isenção', 'restrito');
  t := t || pg_temp.falha('select * from interno.decisoes_isencao', 'candidato lê a tabela de decisões', 'permission denied');

  perform pg_temp.como(ustaff, 'staff-isencao@teste.local');
  select count(*) into n from painel.listar_isencoes() where nome like '%Isencao Teste';
  t := t || pg_temp.igual(n::text, '2', 'Comissão lista os dois pedidos do teste');
  t := t || pg_temp.falha(format('select painel.decidir_isencao(%L, ''deferida'', ''curto'')', ia), 'decisão sem motivo suficiente', 'motivo_obrigatorio');
  t := t || pg_temp.falha(format('select painel.decidir_isencao(%L, ''talvez'', ''motivo com mais de dez caracteres'')', ia), 'decisão inválida', 'decisao_invalida');
  select (painel.decidir_isencao(ia, 'indeferida', 'Documento ilegível e sem número de doação.')).decisao into p;
  t := t || pg_temp.igual(p, 'indeferida', 'Comissão indefere com motivo');
  select decisao into p from painel.listar_isencoes() where inscricao_id = ia;
  t := t || pg_temp.igual(p, 'indeferida', 'lista mostra a decisão registrada');
  select (painel.decidir_isencao(ia, 'deferida', 'Deferida após nova análise do recurso.')).decisao into p;
  select decisao into p from painel.listar_isencoes() where inscricao_id = ia;
  t := t || pg_temp.igual(p, 'deferida', 'nova decisão prevalece (a mais recente)');
  perform pg_temp.admin();
  select count(*) into n from interno.decisoes_isencao where inscricao_id = ia;
  t := t || pg_temp.igual(n::text, '2', 'histórico preserva as duas decisões');
  select count(*) into n from interno.auditoria where entidade = 'interno.decisoes_isencao' and ator_id = ustaff;
  t := t || pg_temp.igual(n::text, '2', 'as decisões ficam na auditoria com o autor');

  -- inscrição sem pedido de isenção não aceita decisão
  update publico.inscricoes set solicitou_isencao = false where id = ib;
  perform pg_temp.como(ustaff, 'staff-isencao@teste.local');
  t := t || pg_temp.falha(format('select painel.decidir_isencao(%L, ''deferida'', ''motivo com mais de dez caracteres'')', ib), 'decidir inscrição sem pedido', 'sem_pedido_de_isencao');

  perform pg_temp.admin();
  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
