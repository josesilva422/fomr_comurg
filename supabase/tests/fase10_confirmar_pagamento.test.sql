-- Fase 10 · Conferência do comprovante do Pix após isenção indeferida (migração 20260925150000): a Comissão confirma o
-- pagamento (inscrição segue o fluxo normal, status 'submetida') ou recusa o comprovante com motivo.
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
-- Uso remoto: colar no SQL Editor do Supabase (ou via MCP execute_sql).
do $teste$
declare
  ustaff constant uuid := 'fa000000-0000-0000-0000-00000000000f';
  ua constant uuid := 'fa000000-0000-0000-0000-00000000000a';  -- indeferida, comprovante recusado e depois confirmado
  ub constant uuid := 'fa000000-0000-0000-0000-00000000000b';  -- indeferida, sem comprovante
  uc constant uuid := 'fa000000-0000-0000-0000-00000000000c';  -- deferida
  ia uuid; ib uuid; ic uuid;
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


  -- inscrições ENCERRADAS (após 13/10) e dentro do prazo de pagamento pós-indeferimento (até 16/10)
  update interno.configuracao set valor = to_jsonb((now() - interval '10 days')::text) where chave = 'inscricoes_abertura';
  update interno.configuracao set valor = to_jsonb((now() - interval '1 day')::text) where chave = 'inscricoes_encerramento';
  update interno.configuracao set valor = to_jsonb((now() + interval '2 days')::text) where chave = 'isencao_pagamento_fim';
  -- em produção o painel exige sessão validada por código; dentro desta transação (desfeita no fim) a exigência é desligada
  update interno.configuracao set valor = 'false'::jsonb where chave = 'painel_exige_login_seguro';
  insert into auth.users (id, aud, role, email) values
    (ustaff, 'authenticated', 'authenticated', 'staff-conf@teste.local'),
    (ua, 'authenticated', 'authenticated', 'conf-a@teste.local'),
    (ub, 'authenticated', 'authenticated', 'conf-b@teste.local'),
    (uc, 'authenticated', 'authenticated', 'conf-c@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email) values (ustaff, 'Comissão Conferência Teste', 'staff-conf@teste.local');
  insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade) values
    (ua, 'Ana Conferência Teste', '52998224725', '62999990000', '1988-03-14', 'brasileiro_nato'),
    (ub, 'Bia Conferência Teste', '39053344705', '62988880000', '1990-05-20', 'brasileiro_nato'),
    (uc, 'Cid Conferência Teste', '11144477735', '62977770000', '1992-07-01', 'brasileiro_nato');
  select i.id into ia from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id where c.user_id = ua;
  select i.id into ib from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id where c.user_id = ub;
  select i.id into ic from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id where c.user_id = uc;
  update publico.inscricoes set status = 'aguardando_isencao', solicitou_isencao = true, hipotese_isencao = 'doador_sangue' where id in (ia, ib, ic);

  perform pg_temp.como(ustaff, 'staff-conf@teste.local');
  perform painel.decidir_isencao(ia, 'indeferida', 'Comprovantes de doação ilegíveis.');
  perform painel.decidir_isencao(ib, 'indeferida', 'Menos de 3 doações no período.');
  perform painel.decidir_isencao(ic, 'deferida', 'Documentos conferem com o decreto.');

  -- sem comprovante / sem indeferimento: não há conferência
  t := t || pg_temp.falha(format('select painel.decidir_pagamento_isencao(%L, true, ''Comprovante conferido: dados corretos.'')', ib), 'confirmar sem comprovante', 'sem_comprovante');
  t := t || pg_temp.falha(format('select painel.decidir_pagamento_isencao(%L, true, ''Comprovante conferido: dados corretos.'')', ic), 'confirmar pagamento de isenção deferida', 'exige_isencao_indeferida');

  -- A envia o comprovante
  perform pg_temp.como(ua, 'conf-a@teste.local');
  t := t || pg_temp.passa(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''comprovante_pix'', %L, ''pix.pdf'', repeat(''a'', 64), ''application/pdf'', 1000)', ia, ia || '/comprovante_pix/' || gen_random_uuid() || '.pdf'), 'A anexa o comprovante');
  t := t || pg_temp.falha(format('select painel.decidir_pagamento_isencao(%L, true, ''Eu mesmo confirmo meu pagamento.'')', ia), 'candidato confirma o próprio pagamento', 'Acesso restrito');

  -- Comissão recusa com motivo -> A vê e pode reenviar
  perform pg_temp.como(ustaff, 'staff-conf@teste.local');
  t := t || pg_temp.falha(format('select painel.decidir_pagamento_isencao(%L, false, ''curto'')', ia), 'recusar sem motivo suficiente', 'motivo');
  select (painel.decidir_pagamento_isencao(ia, false, 'CPF do pagador diverge do CPF do candidato (item 4.9.4).')).decisao into p;
  t := t || pg_temp.igual(p, 'pagamento_recusado', 'Comissão recusa o comprovante com motivo');
  perform pg_temp.admin();
  select status::text into p from publico.inscricoes where id = ia;
  t := t || pg_temp.igual(p, 'aguardando_isencao', 'recusa não muda a situação da inscrição');
  perform pg_temp.como(ustaff, 'staff-conf@teste.local');
  select decisao into p from painel.listar_isencoes() where inscricao_id = ia;
  t := t || pg_temp.igual(p, 'pagamento_recusado', 'painel mostra o comprovante recusado');

  perform pg_temp.como(ua, 'conf-a@teste.local');
  select decisao || '|' || pode_pagar into p from publico.minha_isencao();
  t := t || pg_temp.igual(p, 'pagamento_recusado|true', 'A vê a recusa e ainda pode pagar no prazo');
  t := t || pg_temp.passa('update publico.documentos set ativo = false where tipo = ''comprovante_pix''', 'A remove o comprovante recusado');
  t := t || pg_temp.passa(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''comprovante_pix'', %L, ''pix2.pdf'', repeat(''b'', 64), ''application/pdf'', 1000)', ia, ia || '/comprovante_pix/' || gen_random_uuid() || '.pdf'), 'A envia novo comprovante após a recusa');
  -- a exceção da trava de prazo não serve ao candidato
  perform set_config('pss.confirmando_pagamento', 'on', true);
  t := t || pg_temp.falha('update publico.inscricoes set status = ''submetida''', 'A tenta mudar o próprio status', 'permission denied');
  perform set_config('pss.confirmando_pagamento', 'off', true);
  perform pg_temp.admin();
  select status::text into p from publico.inscricoes where id = ia;
  t := t || pg_temp.igual(p, 'aguardando_isencao', 'candidato não muda o próprio status nem com a variável da exceção');

  -- Comissão confirma (depois do encerramento das inscrições) -> fluxo normal
  perform pg_temp.como(ustaff, 'staff-conf@teste.local');
  select (painel.decidir_pagamento_isencao(ia, true, 'Comprovante conferido: nome, CPF, valor, data e E2E conferem.')).decisao into p;
  t := t || pg_temp.igual(p, 'pagamento_confirmado', 'Comissão confirma o pagamento');
  perform pg_temp.admin();
  select status::text into p from publico.inscricoes where id = ia;
  t := t || pg_temp.igual(p, 'submetida', 'confirmado: inscrição segue o fluxo normal (submetida), mesmo após o encerramento');
  perform pg_temp.como(ustaff, 'staff-conf@teste.local');
  select current_setting('pss.confirmando_pagamento', true) into p;
  t := t || pg_temp.igual(p, 'off', 'a exceção da trava de prazo é desligada logo depois');
  t := t || pg_temp.falha(format('select painel.decidir_pagamento_isencao(%L, true, ''Comprovante conferido de novo.'')', ia), 'confirmar duas vezes', 'fora_da_conferencia');
  t := t || pg_temp.falha(format('select painel.decidir_isencao(%L, ''indeferida'', ''Tentativa de indeferir após confirmar.'')', ia), 'indeferir depois do pagamento confirmado', 'pagamento_ja_confirmado');
  select decisao || '|' || status into p from painel.listar_isencoes() where inscricao_id = ia;
  t := t || pg_temp.igual(p, 'pagamento_confirmado|submetida', 'painel mostra pagamento confirmado');

  perform pg_temp.como(ua, 'conf-a@teste.local');
  select pode_pagar::text into p from publico.minha_isencao();
  t := t || pg_temp.igual(p, 'false', 'depois de confirmado o candidato não mexe mais no comprovante');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''comprovante_pix'', %L, ''pix3.pdf'', repeat(''c'', 64), ''application/pdf'', 1000)', ia, ia || '/comprovante_pix/' || gen_random_uuid() || '.pdf'), 'A anexa outro comprovante depois de confirmado', 'inscricoes_fora_do_periodo');

  -- a trava de prazo continua valendo para os demais
  perform pg_temp.como(ub, 'conf-b@teste.local');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''identidade'', %L, ''rg.pdf'', repeat(''d'', 64), ''application/pdf'', 1000)', ib, ib || '/identidade/' || gen_random_uuid() || '.pdf'), 'B anexa outro tipo de documento após o encerramento', 'inscricoes_fora_do_periodo');

  -- desconsiderar também vale depois de comprovante recusado (após o prazo)
  perform pg_temp.como(ub, 'conf-b@teste.local');
  t := t || pg_temp.passa(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''comprovante_pix'', %L, ''pix.pdf'', repeat(''e'', 64), ''application/pdf'', 1000)', ib, ib || '/comprovante_pix/' || gen_random_uuid() || '.pdf'), 'B anexa comprovante');
  perform pg_temp.como(ustaff, 'staff-conf@teste.local');
  perform painel.decidir_pagamento_isencao(ib, false, 'Valor pago diferente de R$ 100,00 (item 4.8).');
  perform pg_temp.admin();
  update interno.configuracao set valor = to_jsonb((now() - interval '1 minute')::text) where chave = 'isencao_pagamento_fim';
  perform pg_temp.como(ustaff, 'staff-conf@teste.local');
  select (painel.decidir_isencao(ib, 'desconsiderada', 'Sem pagamento válido no prazo do item 4.10.2.')).decisao into p;
  t := t || pg_temp.igual(p, 'desconsiderada', 'desconsiderar depois de comprovante recusado e prazo encerrado');

  perform pg_temp.admin();
  select count(*) into n from interno.auditoria where entidade = 'interno.decisoes_isencao' and ator_id = ustaff;
  t := t || pg_temp.igual(n::text, '7', 'todas as decisões ficam na auditoria com o autor (7)');
  select count(*) into n from interno.auditoria where entidade = 'publico.inscricoes' and entidade_id = ia::text and dados_depois ->> 'status' = 'submetida';
  t := t || pg_temp.igual(n::text, '1', 'a mudança de status fica na auditoria');

  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
