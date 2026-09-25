-- Fase 11 · Homologação das inscrições (migração 20260925160000): a Comissão aprova ou rejeita (com explicação); o
-- candidato vê a decisão e consulta o próprio formulário.
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
-- Uso remoto: colar no SQL Editor do Supabase (ou via MCP execute_sql).
do $teste$
declare
  ustaff constant uuid := 'fb000000-0000-0000-0000-00000000000f';
  ua constant uuid := 'fb000000-0000-0000-0000-00000000000a';  -- pagou por Pix
  ub constant uuid := 'fb000000-0000-0000-0000-00000000000b';  -- isenção deferida
  uc constant uuid := 'fb000000-0000-0000-0000-00000000000c';  -- isenção sem decisão (não homologável ainda)
  ud constant uuid := 'fb000000-0000-0000-0000-00000000000d';  -- rascunho
  ia uuid; ib uuid; ic uuid; id_ uuid;
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
  execute $f$create function pg_temp.passa(p_sql text, p_rotulo text) returns text language plpgsql as $b$
    begin
      execute p_sql; return null;
    exception when others then return p_rotulo || ' -> erro inesperado: ' || sqlerrm;
    end $b$
  $f$;



  -- depois do encerramento das inscrições (homologação é até 20/10)
  update interno.configuracao set valor = to_jsonb((now() - interval '10 days')::text) where chave = 'inscricoes_abertura';
  update interno.configuracao set valor = to_jsonb((now() - interval '1 day')::text) where chave = 'inscricoes_encerramento';
  update interno.configuracao set valor = 'false'::jsonb where chave = 'painel_exige_login_seguro';
  insert into auth.users (id, aud, role, email) values
    (ustaff, 'authenticated', 'authenticated', 'staff-hom@teste.local'),
    (ua, 'authenticated', 'authenticated', 'hom-a@teste.local'), (ub, 'authenticated', 'authenticated', 'hom-b@teste.local'),
    (uc, 'authenticated', 'authenticated', 'hom-c@teste.local'), (ud, 'authenticated', 'authenticated', 'hom-d@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email) values (ustaff, 'Comissão Homologação Teste', 'staff-hom@teste.local');
  insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade) values
    (ua, 'Ana Homologação Teste', '52998224725', '62999990000', '1988-03-14', 'brasileiro_nato'),
    (ub, 'Bia Homologação Teste', '39053344705', '62988880000', '1990-05-20', 'brasileiro_nato'),
    (uc, 'Cid Homologação Teste', '11144477735', '62977770000', '1992-07-01', 'brasileiro_nato'),
    (ud, 'Dan Homologação Teste', '22233344316', '62966660000', '1993-08-02', 'brasileiro_nato');
  select i.id into ia from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id where c.user_id = ua;
  select i.id into ib from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id where c.user_id = ub;
  select i.id into ic from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id where c.user_id = uc;
  select i.id into id_ from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id where c.user_id = ud;
  update publico.inscricoes set status = 'submetida', grupo = 'A', nivel = 'junior', submetida_em = now() where id = ia;
  update publico.inscricoes set status = 'aguardando_isencao', solicitou_isencao = true, hipotese_isencao = 'doador_sangue', submetida_em = now() where id in (ib, ic);

  perform pg_temp.como(ustaff, 'staff-hom@teste.local');
  perform painel.decidir_isencao(ib, 'deferida', 'Documentos conferem com o decreto.');

  -- lista: A (Pix) e B (isenção deferida); C (isenção sem decisão) e D (rascunho) ficam de fora
  select string_agg(split_part(x.nome, ' ', 1) || ':' || x.pagamento, ',' order by x.nome) into p
    from painel.listar_homologacao() x where x.nome like '%Homologação Teste';
  t := t || pg_temp.igual(p, 'Ana:pix,Bia:isencao', 'lista traz só as homologáveis, com a forma de pagamento: ' || coalesce(p, 'nenhuma'));
  t := t || pg_temp.falha(format('select painel.decidir_inscricao(%L, true, null)', ic), 'homologar com isenção sem decisão', 'fora_da_homologacao');
  t := t || pg_temp.falha(format('select painel.decidir_inscricao(%L, true, null)', id_), 'homologar rascunho', 'fora_da_homologacao');

  -- rejeitar exige explicação
  t := t || pg_temp.falha(format('select painel.decidir_inscricao(%L, false, ''curto'')', ia), 'rejeitar sem explicação', 'motivo');
  select (painel.decidir_inscricao(ia, false, 'CPF do pagador do Pix diverge do CPF do candidato (item 4.9.4).')).decisao into p;
  t := t || pg_temp.igual(p, 'rejeitada', 'rejeita com explicação (após o encerramento)');
  perform pg_temp.admin();
  select status::text into p from publico.inscricoes where id = ia;
  t := t || pg_temp.igual(p, 'indeferida', 'rejeitada -> status indeferida');

  perform pg_temp.como(ua, 'hom-a@teste.local');
  select decisao || '|' || coalesce(motivo, '-') into p from publico.minha_decisao_inscricao();
  t := t || pg_temp.igual((p like 'rejeitada|CPF do pagador%')::text, 'true', 'candidato vê a rejeição com o motivo: ' || coalesce(p, 'nada'));

  -- nova decisão (ex.: após recurso): aprovar, sem motivo
  perform pg_temp.como(ustaff, 'staff-hom@teste.local');
  select (painel.decidir_inscricao(ia, true, null)).decisao into p;
  t := t || pg_temp.igual(p, 'aprovada', 'aprova sem precisar de motivo');
  perform pg_temp.admin();
  select status::text into p from publico.inscricoes where id = ia;
  t := t || pg_temp.igual(p, 'homologada', 'aprovada -> status homologada');
  perform pg_temp.como(ua, 'hom-a@teste.local');
  select decisao || '|' || coalesce(motivo, '-') into p from publico.minha_decisao_inscricao();
  t := t || pg_temp.igual(p, 'aprovada|-', 'candidato vê só "aprovada", sem motivo');

  -- isenção deferida também é homologada
  perform pg_temp.como(ustaff, 'staff-hom@teste.local');
  perform painel.decidir_inscricao(ib, true, 'Isenção deferida e inscrição completa.');
  perform pg_temp.como(ub, 'hom-b@teste.local');
  select decisao || '|' || coalesce(motivo, '-') into p from publico.minha_decisao_inscricao();
  t := t || pg_temp.igual(p, 'aprovada|-', 'aprovação com observação interna: o candidato não vê o texto');

  -- formulário: cada um vê só o próprio
  perform pg_temp.como(ua, 'hom-a@teste.local');
  j := publico.meu_formulario();
  t := t || pg_temp.igual(j ->> 'nome', 'Ana Homologação Teste', 'candidato vê o próprio formulário');
  t := t || pg_temp.igual(j ->> 'status', 'homologada', 'formulário mostra a situação atual');
  perform pg_temp.como(ud, 'hom-d@teste.local');
  t := t || pg_temp.igual(publico.meu_formulario() ->> 'nome', 'Dan Homologação Teste', 'outro candidato vê só o dele');
  select count(*)::text into p from publico.minha_decisao_inscricao();
  t := t || pg_temp.igual(p, '0', 'sem decisão, nada a mostrar');

  -- acesso
  t := t || pg_temp.falha('select * from painel.listar_homologacao()', 'candidato lista a homologação', 'Acesso restrito');
  t := t || pg_temp.falha(format('select painel.decidir_inscricao(%L, true, null)', id_), 'candidato decide inscrição', 'Acesso restrito');
  t := t || pg_temp.falha('select * from interno.decisoes_inscricao', 'candidato lê as decisões', 'permission denied');
  perform pg_temp.como(ua, 'hom-a@teste.local');
  perform set_config('pss.decisao_comissao', 'on', true);
  t := t || pg_temp.falha('update publico.inscricoes set status = ''homologada''', 'candidato muda o próprio status com a variável', 'permission denied');
  perform set_config('pss.decisao_comissao', 'off', true);

  -- rejeitada sai da análise curricular/convocação; auditoria
  perform pg_temp.admin();
  select count(*) into n from interno.auditoria where entidade = 'interno.decisoes_inscricao' and ator_id = ustaff;
  t := t || pg_temp.igual(n::text, '3', 'as decisões ficam na auditoria com o autor (3)');

  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
