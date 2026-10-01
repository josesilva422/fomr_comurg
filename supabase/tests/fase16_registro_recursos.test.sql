-- Fase 16 · Registro de recursos (migração 20261001220000_registro_recursos.sql): interno.recursos,
-- painel.registrar_recurso, painel.decidir_recurso, painel.listar_recursos — Capítulo IX do edital
-- (9.1, 9.2); item 4.13 (minuta v11) quando o recurso é contra o indeferimento da inscrição e é deferido.
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
-- Uso remoto: colar no SQL Editor do Supabase (ou via MCP execute_sql).
do $teste$
declare
  ustaff constant uuid := 'f6000000-0000-0000-0000-00000000000f';
  ssid constant uuid := gen_random_uuid();
  ua constant uuid := 'f6000000-0000-0000-0000-000000000001';
  i_a uuid;
  r_id uuid;
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

  insert into auth.users (id, aud, role, email) values (ustaff, 'authenticated', 'authenticated', 'staff-rec@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email) values (ustaff, 'Comissão Recursos Teste', 'staff-rec@teste.local');
  insert into interno.sessoes_painel (session_id, user_id) values (ssid, ustaff);

  insert into auth.users (id, aud, role, email) values (ua, 'authenticated', 'authenticated', 'rec-a@teste.local');
  insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade)
    values (ua, 'Recurso Teste A', '11144477735', '62999990000', '1988-03-14', 'brasileiro_nato');
  select i.id into i_a from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id where c.user_id = ua;
  update publico.inscricoes set status = 'indeferida', grupo = 'A', nivel = 'junior', submetida_em = now() where id = i_a;

  perform pg_temp.como(ustaff, 'staff-rec@teste.local', ssid);

  ---------------------------------------------------------------- validações
  t := t || pg_temp.falha(format('select painel.registrar_recurso(%L, ''etapa_invalida'', current_date, ''fundamentação de teste'')', i_a),
    'etapa inválida', 'etapa_invalida');
  t := t || pg_temp.falha(format('select painel.registrar_recurso(%L, ''inscricao'', current_date, ''oi'')', i_a),
    'fundamentação curta', 'fundamentacao_obrigatoria');
  t := t || pg_temp.falha(format('select painel.registrar_recurso(gen_random_uuid(), ''inscricao'', current_date, ''fundamentação de teste'')'),
    'inscrição inexistente', 'nao_encontrada');

  ---------------------------------------------------------------- registro
  select (painel.registrar_recurso(i_a, 'inscricao', '2026-10-29'::date,
    'CPF do pagador do Pix é o mesmo do candidato; a divergência apontada é erro de leitura do comprovante.')).id into r_id;
  select decisao into p from painel.listar_recursos() where id = r_id;
  t := t || pg_temp.igual(p, 'pendente', 'recurso registrado como pendente');

  t := t || pg_temp.falha(format('select painel.decidir_recurso(%L, true, ''curto'')', r_id), 'decidir sem motivo suficiente', 'motivo_obrigatorio');
  t := t || pg_temp.falha('select painel.decidir_recurso(gen_random_uuid(), true, ''motivo de teste suficiente'')', 'recurso inexistente', 'nao_encontrado');

  ---------------------------------------------------------------- deferido contra indeferimento de inscrição -> volta a homologada (item 4.13)
  perform painel.decidir_recurso(r_id, true, 'Conferido o comprovante original: o CPF do pagador confere com o do candidato.');
  select decisao into p from painel.listar_recursos() where id = r_id;
  t := t || pg_temp.igual(p, 'deferido', 'recurso marcado como deferido');
  perform pg_temp.admin();
  select status::text into p from publico.inscricoes where id = i_a;
  t := t || pg_temp.igual(p, 'homologada', 'inscrição volta a homologada após recurso deferido (item 4.13)');
  perform pg_temp.como(ustaff, 'staff-rec@teste.local', ssid);

  ---------------------------------------------------------------- indeferido não altera o status da inscrição
  perform pg_temp.admin();
  update publico.inscricoes set status = 'indeferida' where id = i_a;
  perform pg_temp.como(ustaff, 'staff-rec@teste.local', ssid);
  select (painel.registrar_recurso(i_a, 'ac', '2026-11-10'::date, 'Discordância da pontuação de experiência atribuída pelo motor.')).id into r_id;
  perform painel.decidir_recurso(r_id, false, 'A experiência apontada não tem comprovante anexado, conforme item 5.3.');
  perform pg_temp.admin();
  select status::text into p from publico.inscricoes where id = i_a;
  t := t || pg_temp.igual(p, 'indeferida', 'recurso de etapa AC não altera o status da inscrição (só o de inscrição, item 4.13)');
  perform pg_temp.como(ustaff, 'staff-rec@teste.local', ssid);

  ---------------------------------------------------------------- acesso
  perform pg_temp.como(ua, 'rec-a@teste.local', gen_random_uuid());
  t := t || pg_temp.falha('select * from painel.listar_recursos()', 'candidato lista recursos', 'Acesso restrito');
  t := t || pg_temp.falha(format('select painel.registrar_recurso(%L, ''inscricao'', current_date, ''fundamentação de teste'')', i_a),
    'candidato registra recurso', 'Acesso restrito');
  t := t || pg_temp.falha('select * from interno.recursos', 'candidato lê a tabela direto', 'permission denied');

  ---------------------------------------------------------------- auditoria
  perform pg_temp.admin();
  select count(*) into n from interno.auditoria where entidade = 'interno.recursos' and ator_id = ustaff;
  t := t || pg_temp.igual(n::text, '4', 'cada registro e decisão de recurso fica na auditoria (2 registros + 2 decisões)');

  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
