-- Fase 7 · Convite de usuários do painel (migração 20260924170000): token de 12 h, uso único, e-mail conferido,
-- cadastro com nome/CPF/senha, sessão liberada só após o aceite. Roda numa transação desfeita no final.
do $teste$
declare
  ui constant uuid := 'f4000000-0000-0000-0000-00000000000a';  -- quem convida
  un constant uuid := 'f4000000-0000-0000-0000-00000000000b';  -- membro sem permissão de convidar
  uv constant uuid := 'f4000000-0000-0000-0000-00000000000c';  -- convidado (conta criada pelo Auth ao digitar o código)
  ux constant uuid := 'f4000000-0000-0000-0000-00000000000d';  -- outra pessoa
  si constant uuid := 'f5000000-0000-0000-0000-000000000001';
  sn constant uuid := 'f5000000-0000-0000-0000-000000000002';
  sv constant uuid := 'f5000000-0000-0000-0000-000000000003';
  sx constant uuid := 'f5000000-0000-0000-0000-000000000004';
  t text[] := '{}';
  total integer; nf integer; n integer;
  tk text; tk2 text; b boolean;
begin
  execute $f$create function pg_temp.como(p_uid uuid, p_sess uuid, p_email text) returns void language plpgsql as $b$
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'session_id', p_sess, 'email', p_email)::text, true);
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

  insert into auth.users (id, aud, role, email) values
    (ui, 'authenticated', 'authenticated', 'convida@teste.local'),
    (un, 'authenticated', 'authenticated', 'semperm@teste.local'),
    (uv, 'authenticated', 'authenticated', 'novo@teste.local'),
    (ux, 'authenticated', 'authenticated', 'outro@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email, pode_convidar) values
    (ui, 'Quem Convida Teste', 'convida@teste.local', true),
    (un, 'Sem Permissao Teste', 'semperm@teste.local', false);
  update interno.configuracao set valor = to_jsonb(true) where chave = 'painel_exige_login_seguro';
  insert into interno.sessoes_painel (session_id, user_id) values (si, ui), (sn, un);

  ---------------------------------------------------------------- permissão de convidar
  perform pg_temp.como(un, sn, 'semperm@teste.local');
  t := t || pg_temp.falha('select painel.criar_convite(''novo@teste.local'')', 'membro sem permissão convida', 'permissão');
  select painel.posso_convidar() into b;
  t := t || pg_temp.igual(b::text, 'false', 'posso_convidar = false para quem não tem permissão');
  perform pg_temp.como(uv, sv, 'novo@teste.local');
  t := t || pg_temp.falha('select painel.criar_convite(''x@teste.local'')', 'candidato/desconhecido convida', 'permissão');

  perform pg_temp.como(ui, si, 'convida@teste.local');
  select painel.posso_convidar() into b;
  t := t || pg_temp.igual(b::text, 'true', 'posso_convidar = true para quem tem permissão');
  t := t || pg_temp.falha('select painel.criar_convite(''nao-e-email'')', 'e-mail inválido', 'email_invalido');
  t := t || pg_temp.falha('select painel.criar_convite(''semperm@teste.local'')', 'convidar quem já é usuário', 'ja_e_usuario');
  select painel.criar_convite('  Novo@Teste.Local ') into tk;
  t := t || pg_temp.igual((length(tk) = 64)::text, 'true', 'token de 64 caracteres (32 bytes)');
  perform pg_temp.admin();
  select count(*) into n from interno.convites_painel where token_hash = tk;
  t := t || pg_temp.igual(n::text, '0', 'o token em si não é guardado (só o hash)');
  select count(*) into n from interno.convites_painel where email = 'novo@teste.local' and expira_em - criado_em = interval '12 hours';
  t := t || pg_temp.igual(n::text, '1', 'convite vale 12 horas e o e-mail é normalizado');

  ---------------------------------------------------------------- conferir (antes do código)
  perform pg_temp.anonimo();
  select painel.conferir_convite(tk, 'NOVO@teste.local') into b;
  t := t || pg_temp.igual(b::text, 'true', 'token + e-mail certos (sem diferenciar caixa)');
  select painel.conferir_convite(tk, 'outro@teste.local') into b;
  t := t || pg_temp.igual(b::text, 'false', 'e-mail diferente do convite é recusado');
  select painel.conferir_convite('0000', 'novo@teste.local') into b;
  t := t || pg_temp.igual(b::text, 'false', 'token inventado é recusado');

  ---------------------------------------------------------------- aceite
  perform pg_temp.como(ux, sx, 'outro@teste.local');
  t := t || pg_temp.falha(format('select painel.aceitar_convite(%L, ''Outra Pessoa Silva'', ''52998224725'', ''Senha@12345'')', tk), 'outro e-mail usa o token', 'convite_invalido');
  perform pg_temp.como(uv, sv, 'novo@teste.local');
  select painel.sou_da_comissao() into b;
  t := t || pg_temp.igual(b::text, 'false', 'antes do aceite não é da Comissão');
  t := t || pg_temp.falha(format('select painel.aceitar_convite(%L, ''Novo'', ''52998224725'', ''Senha@12345'')', tk), 'nome sem sobrenome', 'nome_invalido');
  t := t || pg_temp.falha(format('select painel.aceitar_convite(%L, ''Novo Usuario Teste'', ''11111111111'', ''Senha@12345'')', tk), 'CPF inválido', 'cpf_invalido');
  t := t || pg_temp.falha(format('select painel.aceitar_convite(%L, ''Novo Usuario Teste'', ''52998224725'', ''senhafraca'')', tk), 'senha fraca', 'senha_fraca');
  t := t || pg_temp.falha('select painel.aceitar_convite(''0000'', ''Novo Usuario Teste'', ''52998224725'', ''Senha@12345'')', 'token inventado no aceite', 'convite_invalido');
  select painel.aceitar_convite(tk, 'Novo Usuario Teste', '529.982.247-25', 'Senha@12345') into b;
  t := t || pg_temp.igual(b::text, 'true', 'aceite com dados válidos');
  select painel.sou_da_comissao() into b;
  t := t || pg_temp.igual(b::text, 'true', 'depois do aceite a sessão vê o painel');
  t := t || pg_temp.falha(format('select painel.aceitar_convite(%L, ''Novo Usuario Teste'', ''52998224725'', ''Senha@12345'')', tk), 'reusar o token', 'convite_invalido');

  perform pg_temp.admin();
  select count(*) into n from interno.usuarios_internos where user_id = uv and cpf = '52998224725' and senha_hash is not null and convidado_por = ui and perfil = 'comissao';
  t := t || pg_temp.igual(n::text, '1', 'usuário criado com CPF só dígitos, senha em hash e quem convidou');
  select count(*) into n from interno.usuarios_internos where user_id = uv and senha_hash = 'Senha@12345';
  t := t || pg_temp.igual(n::text, '0', 'a senha não é guardada em texto');
  select count(*) into n from interno.auditoria where entidade = 'interno.convites_painel' and ator_id = ui and acao = 'INSERT';
  t := t || pg_temp.igual(n::text, '1', 'criação do convite auditada com o autor');
  select count(*) into n from interno.auditoria where entidade = 'interno.convites_painel' and ator_id = uv and acao = 'UPDATE';
  t := t || pg_temp.igual(n::text, '1', 'aceite auditado com o autor');

  -- login normal depois do aceite: senha escolhida funciona
  perform pg_temp.anonimo();
  select painel.iniciar_login('novo@teste.local', 'Senha@12345') into b;
  t := t || pg_temp.igual(b::text, 'true', 'a senha escolhida no aceite abre o login normal');

  ---------------------------------------------------------------- validade e cancelamento
  perform pg_temp.como(ui, si, 'convida@teste.local');
  select painel.criar_convite('velho@teste.local') into tk;
  perform pg_temp.admin();
  update interno.convites_painel set expira_em = now() - interval '1 minute' where email = 'velho@teste.local';
  perform pg_temp.anonimo();
  select painel.conferir_convite(tk, 'velho@teste.local') into b;
  t := t || pg_temp.igual(b::text, 'false', 'convite expirado (12 h) é recusado');

  perform pg_temp.como(ui, si, 'convida@teste.local');
  select painel.criar_convite('duplo@teste.local') into tk;
  select painel.criar_convite('duplo@teste.local') into tk2;
  perform pg_temp.anonimo();
  select painel.conferir_convite(tk, 'duplo@teste.local') into b;
  t := t || pg_temp.igual(b::text, 'false', 'novo convite cancela o anterior do mesmo e-mail');
  select painel.conferir_convite(tk2, 'duplo@teste.local') into b;
  t := t || pg_temp.igual(b::text, 'true', 'o convite mais recente vale');

  -- listagem
  perform pg_temp.como(ui, si, 'convida@teste.local');
  select count(*) into n from painel.listar_convites() where email = 'novo@teste.local' and situacao = 'aceito';
  t := t || pg_temp.igual(n::text, '1', 'lista mostra o convite aceito');
  select count(*) into n from painel.listar_convites() where email = 'velho@teste.local' and situacao = 'expirado';
  t := t || pg_temp.igual(n::text, '1', 'lista mostra o convite expirado');
  t := t || pg_temp.falha('select * from interno.convites_painel', 'membro lê a tabela de convites direto', 'permission denied');

  perform pg_temp.admin();
  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
