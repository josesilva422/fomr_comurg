-- Fase 8 · Pagamento após isenção indeferida (edital 4.10.2 / 4.9.5, migração 20260924180000).
-- Roda inteiro dentro de UMA transação que é desfeita no final: não deixa nenhum dado.
do $teste$
declare
  ustaff constant uuid := 'f6000000-0000-0000-0000-00000000000f';
  ua constant uuid := 'f6000000-0000-0000-0000-00000000000a';  -- isenção indeferida
  ub constant uuid := 'f6000000-0000-0000-0000-00000000000b';  -- isenção deferida
  uc constant uuid := 'f6000000-0000-0000-0000-00000000000c';  -- sem decisão ainda
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
  insert into auth.users (id, aud, role, email) values
    (ustaff, 'authenticated', 'authenticated', 'staff-pag@teste.local'),
    (ua, 'authenticated', 'authenticated', 'pag-a@teste.local'),
    (ub, 'authenticated', 'authenticated', 'pag-b@teste.local'),
    (uc, 'authenticated', 'authenticated', 'pag-c@teste.local');
  insert into interno.usuarios_internos (user_id, nome, email) values (ustaff, 'Comissão Pagamento Teste', 'staff-pag@teste.local');

  -- cadastros (o período está encerrado: criamos como administrador e depois simulamos o login de cada um)
  insert into publico.candidatos (user_id, nome, cpf, telefone, data_nascimento, nacionalidade) values
    (ua, 'Ana Pagamento Teste', '52998224725', '62999990000', '1988-03-14', 'brasileiro_nato'),
    (ub, 'Bia Pagamento Teste', '39053344705', '62988880000', '1990-05-20', 'brasileiro_nato'),
    (uc, 'Cid Pagamento Teste', '11144477735', '62977770000', '1992-07-01', 'brasileiro_nato');
  select i.id into ia from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id where c.user_id = ua;
  select i.id into ib from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id where c.user_id = ub;
  select i.id into ic from publico.inscricoes i join publico.candidatos c on c.id = i.candidato_id where c.user_id = uc;
  update publico.inscricoes set status = 'aguardando_isencao', solicitou_isencao = true, hipotese_isencao = 'doador_sangue'
   where id in (ia, ib, ic);

  perform pg_temp.como(ustaff, 'staff-pag@teste.local');
  perform painel.decidir_isencao(ia, 'indeferida', 'Comprovantes ilegíveis e sem número.');
  perform painel.decidir_isencao(ib, 'deferida', 'Documentos conferem com o decreto.');

  ---------------------------------------------------------------- A: isenção indeferida, dentro do prazo
  perform pg_temp.como(ua, 'pag-a@teste.local');
  select decisao into p from publico.minha_isencao();
  t := t || pg_temp.igual(p, 'indeferida', 'candidato vê a decisão sobre o próprio pedido');
  select pode_pagar into b from publico.minha_isencao();
  t := t || pg_temp.igual(b::text, 'true', 'pode pagar dentro do prazo');
  select motivo into p from publico.minha_isencao();
  t := t || pg_temp.igual((p like 'Comprovantes ilegíveis%')::text, 'true', 'candidato vê o motivo do indeferimento');
  t := t || pg_temp.passa(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''comprovante_pix'', %L, ''pix.pdf'', repeat(''a'', 64), ''application/pdf'', 1000)', ia, ia || '/comprovante_pix/' || gen_random_uuid() || '.pdf'), 'A anexa o comprovante depois do encerramento');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''identidade'', %L, ''rg.pdf'', repeat(''b'', 64), ''application/pdf'', 1000)', ia, ia || '/identidade/' || gen_random_uuid() || '.pdf'), 'A anexa outro tipo de documento', 'inscricoes_fora_do_periodo');
  t := t || pg_temp.passa(format('insert into storage.objects (bucket_id, name) values (''documentos'', %L)', ia || '/comprovante_pix/a.pdf'), 'A envia o arquivo do comprovante');
  t := t || pg_temp.falha(format('insert into storage.objects (bucket_id, name) values (''documentos'', %L)', ia || '/identidade/a.pdf'), 'A envia arquivo de outro tipo', 'row-level security');
  t := t || pg_temp.falha(format('insert into storage.objects (bucket_id, name) values (''documentos'', %L)', ib || '/comprovante_pix/a.pdf'), 'A envia comprovante na pasta de B', 'row-level security');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''comprovante_pix'', %L, ''pix.pdf'', repeat(''c'', 64), ''application/pdf'', 1000)', ib, ib || '/comprovante_pix/' || gen_random_uuid() || '.pdf'), 'A anexa comprovante na inscrição de B', 'inscricoes_fora_do_periodo');
  t := t || pg_temp.passa('update publico.documentos set ativo = false where tipo = ''comprovante_pix''', 'A remove o próprio comprovante (soft)');
  select count(*) into n from publico.documentos where tipo = 'comprovante_pix' and not ativo;
  t := t || pg_temp.igual(n::text, '1', 'remoção do comprovante registrada');
  t := t || pg_temp.passa(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''comprovante_pix'', %L, ''pix2.pdf'', repeat(''d'', 64), ''application/pdf'', 1000)', ia, ia || '/comprovante_pix/' || gen_random_uuid() || '.pdf'), 'A reenvia o comprovante');
  t := t || pg_temp.passa('update publico.inscricoes set grupo = ''C''', 'A tenta alterar a inscrição (RLS filtra: 0 linhas)');
  select grupo::text into p from publico.inscricoes;
  t := t || pg_temp.igual(p, null, 'a inscrição de A continua selada');

  ---------------------------------------------------------------- B (deferida) e C (sem decisão) não pagam por essa janela
  perform pg_temp.como(ub, 'pag-b@teste.local');
  select pode_pagar into b from publico.minha_isencao();
  t := t || pg_temp.igual(b::text, 'false', 'isenção deferida: não há taxa a pagar');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''comprovante_pix'', %L, ''pix.pdf'', repeat(''e'', 64), ''application/pdf'', 1000)', ib, ib || '/comprovante_pix/' || gen_random_uuid() || '.pdf'), 'B (deferida) anexa comprovante', 'inscricoes_fora_do_periodo');
  perform pg_temp.como(uc, 'pag-c@teste.local');
  select count(*) into n from publico.minha_isencao();
  t := t || pg_temp.igual(n::text, '0', 'sem decisão a candidata não vê nada');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''comprovante_pix'', %L, ''pix.pdf'', repeat(''f'', 64), ''application/pdf'', 1000)', ic, ic || '/comprovante_pix/' || gen_random_uuid() || '.pdf'), 'C (sem decisão) anexa comprovante', 'inscricoes_fora_do_periodo');

  ---------------------------------------------------------------- Comissão: desconsiderar só depois do prazo
  perform pg_temp.como(ustaff, 'staff-pag@teste.local');
  select count(*) into n from painel.listar_isencoes() where inscricao_id = ia and comprovante_enviado;
  t := t || pg_temp.igual(n::text, '1', 'painel mostra que A enviou comprovante');
  t := t || pg_temp.falha(format('select painel.decidir_isencao(%L, ''desconsiderada'', ''Sem pagamento no prazo do item 4.10.2.'')', ia), 'desconsiderar antes do fim do prazo', 'prazo_de_pagamento_aberto');
  t := t || pg_temp.falha(format('select painel.decidir_isencao(%L, ''desconsiderada'', ''Sem pagamento no prazo do item 4.10.2.'')', ib), 'desconsiderar isenção deferida', 'desconsiderar_exige_indeferida');

  perform pg_temp.admin();
  update interno.configuracao set valor = to_jsonb((now() - interval '1 minute')::text) where chave = 'isencao_pagamento_fim';

  perform pg_temp.como(ua, 'pag-a@teste.local');
  select pode_pagar into b from publico.minha_isencao();
  t := t || pg_temp.igual(b::text, 'false', 'depois de 16/10 23h59 não pode mais pagar');
  t := t || pg_temp.falha(format('insert into publico.documentos (inscricao_id, tipo, storage_path, nome_original, sha256, mime, tamanho_bytes) values (%L, ''comprovante_pix'', %L, ''pix3.pdf'', repeat(''9'', 64), ''application/pdf'', 1000)', ia, ia || '/comprovante_pix/' || gen_random_uuid() || '.pdf'), 'A anexa comprovante depois do prazo', 'inscricoes_fora_do_periodo');

  perform pg_temp.como(ustaff, 'staff-pag@teste.local');
  select (painel.decidir_isencao(ia, 'desconsiderada', 'Sem pagamento válido no prazo do item 4.10.2.')).decisao into p;
  t := t || pg_temp.igual(p, 'desconsiderada', 'Comissão desconsidera com motivo depois do prazo');
  perform pg_temp.como(ua, 'pag-a@teste.local');
  select decisao into p from publico.minha_isencao();
  t := t || pg_temp.igual(p, 'desconsiderada', 'candidato é informado da decisão');

  perform pg_temp.admin();
  select count(*) into n from interno.auditoria where entidade = 'interno.decisoes_isencao' and ator_id = ustaff;
  t := t || pg_temp.igual(n::text, '3', 'as três decisões ficam na auditoria com o autor');

  select count(*), count(x) into total, nf from unnest(t) x;
  raise exception 'RESULTADO_DOS_TESTES: % verificações, % falhas%', total, nf,
    case when nf > 0 then E'\n' || (select string_agg(x, E'\n') from unnest(t) x where x is not null) else ' — TODOS PASSARAM' end;
end;
$teste$;
