-- Fase 6 · Login do painel: senha + código por e-mail exigidos pelo banco (migração 20260924150000).
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
do $teste$
declare
  us constant uuid := 'f2000000-0000-0000-0000-00000000000a';
  uc constant uuid := 'f2000000-0000-0000-0000-00000000000b';
  s1 constant uuid := 'f3000000-0000-0000-0000-000000000001';
  s2 constant uuid := 'f3000000-0000-0000-0000-000000000002';
  t text[] := '{}';
  n integer; total integer; nf integer;
  b boolean;
begin
  execute $f$create function pg_temp.como(p_uid uuid, p_sess uuid) returns void language plpgsql as $b$
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'session_id', p_sess)::text, true);
      execute 'set local role authenticated';
    end $b$
  $f$;
  execute $f$create function pg_temp.anonimo() returns void language plpgsql as $b$
    begin
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
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
  execute $f$create function pg_temp.falha(p_sql text, p_rotulo text, p_trecho text default null) returns text language plpgsql as $b$
    declare v_msg text;
    begin
      execute p_sql;
      return p_rotulo || ' -> deveria falhar e passou';
    exception when others then
      v_msg := sqlerrm;
      if p_trecho is not null and v_msg not ilike ('%' || p_trecho || '%') then
        return p_rotulo || ' -> falhou com outro erro: ' || v_msg;
      end if;
      return null;
    end $b$
  $f$;

  insert into auth.users (id, aud, role, email) values
    (us, 'authenticated', 'authenticated', 'staff-login@teste.local'),
    (uc, 'authenticated', 'authenticated', 'cand-login@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email) values (us, 'Comissão Login Teste', 'staff-login@teste.local');
  perform interno.definir_senha_painel('staff-login@teste.local', 'senha-de-teste-123');

  ---------------------------------------------------------------- interruptor desligado: comportamento antigo
  perform pg_temp.como(us, s1);
  select painel.sou_da_comissao() into b;
  t := t || pg_temp.igual(b::text, 'true', 'interruptor desligado: membro passa sem marca de sessão');

  ---------------------------------------------------------------- interruptor ligado
  perform pg_temp.admin();
  update interno.configuracao set valor = to_jsonb(true) where chave = 'painel_exige_login_seguro';
  perform pg_temp.como(us, s1);
  select painel.sou_da_comissao() into b;
  t := t || pg_temp.igual(b::text, 'false', 'ligado: sessão sem senha+código NÃO é Comissão (mesmo membro)');
  t := t || pg_temp.falha('select * from painel.listar_isencoes()', 'ligado: função do painel bloqueada sem sessão liberada', 'restrito');
  select painel.concluir_login() into b;
  t := t || pg_temp.igual(b::text, 'false', 'concluir_login sem senha conferida antes é recusado');
  select painel.sou_da_comissao() into b;
  t := t || pg_temp.igual(b::text, 'false', 'continua bloqueado após tentar concluir sem senha');

  -- senha errada
  perform pg_temp.anonimo();
  select painel.iniciar_login('staff-login@teste.local', 'errada') into b;
  t := t || pg_temp.igual(b::text, 'false', 'senha errada é recusada');
  select painel.iniciar_login('naoexiste@teste.local', 'qualquer') into b;
  t := t || pg_temp.igual(b::text, 'false', 'e-mail que não é do painel é recusado');
  perform pg_temp.como(uc, s2);
  select painel.iniciar_login('cand-login@teste.local', 'qualquer') into b;
  t := t || pg_temp.igual(b::text, 'false', 'candidato (fora da lista) é recusado');
  select painel.concluir_login() into b;
  t := t || pg_temp.igual(b::text, 'false', 'candidato não conclui login do painel');

  -- senha correta, mas sessão de outro usuário não aproveita o desafio
  perform pg_temp.anonimo();
  select painel.iniciar_login('STAFF-login@teste.local', 'senha-de-teste-123') into b;
  t := t || pg_temp.igual(b::text, 'true', 'senha correta abre o desafio (e-mail sem diferenciar caixa)');
  perform pg_temp.como(uc, s2);
  select painel.concluir_login() into b;
  t := t || pg_temp.igual(b::text, 'false', 'outro usuário não aproveita o desafio do membro');

  -- fluxo completo
  perform pg_temp.como(us, s1);
  select painel.concluir_login() into b;
  t := t || pg_temp.igual(b::text, 'true', 'com senha conferida, o código libera a sessão');
  select painel.sou_da_comissao() into b;
  t := t || pg_temp.igual(b::text, 'true', 'sessão liberada é Comissão');
  select painel.concluir_login() into b;
  t := t || pg_temp.igual(b::text, 'false', 'o desafio vale uma só vez');
  -- outra sessão do mesmo usuário (ex.: sessão criada só com o código pedido direto ao Auth) não é liberada
  perform pg_temp.como(us, s2);
  select painel.sou_da_comissao() into b;
  t := t || pg_temp.igual(b::text, 'false', 'outra sessão do mesmo usuário, sem senha, continua bloqueada');

  -- validade da sessão (12 h)
  perform pg_temp.admin();
  update interno.sessoes_painel set criada_em = now() - interval '13 hours' where session_id = s1;
  perform pg_temp.como(us, s1);
  select painel.sou_da_comissao() into b;
  t := t || pg_temp.igual(b::text, 'false', 'sessão liberada há mais de 12 h expira');

  -- bloqueio por tentativas
  perform pg_temp.anonimo();
  for n in 1..5 loop perform painel.iniciar_login('staff-login@teste.local', 'errada'); end loop;
  select painel.iniciar_login('staff-login@teste.local', 'senha-de-teste-123') into b;
  t := t || pg_temp.igual(b::text, 'false', 'após 5 erros a conta fica bloqueada, mesmo com a senha certa');
  perform pg_temp.admin();
  update interno.usuarios_internos set bloqueado_ate = now() - interval '1 minute' where user_id = us;
  perform pg_temp.anonimo();
  select painel.iniciar_login('staff-login@teste.local', 'senha-de-teste-123') into b;
  t := t || pg_temp.igual(b::text, 'true', 'passado o bloqueio, a senha certa volta a funcionar');

  -- tabelas internas não são lidas por candidato/anon, nem senha_hash
  perform pg_temp.como(us, s1);
  t := t || pg_temp.falha('select senha_hash from interno.usuarios_internos', 'membro lê hash de senha direto', 'permission denied');
  t := t || pg_temp.falha('select * from interno.sessoes_painel', 'membro lê sessões direto', 'permission denied');
  t := t || pg_temp.falha('select interno.definir_senha_painel(''staff-login@teste.local'', ''outra-senha-longa'')', 'membro troca senha pela API', 'permission denied');

  perform pg_temp.admin();
  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
