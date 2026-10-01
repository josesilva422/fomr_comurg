-- Volta a abertura e os itens 3, 12, 13 e 24 do cronograma para os valores da minuta v9 (29/09/2026).
update interno.configuracao
   set valor = to_jsonb('2026-10-05T00:00:00-03:00'::text),
       descricao = 'Abertura das inscrições (edital publicado, minuta v9).'
 where chave = 'inscricoes_abertura';

do $$
declare v_uid uuid; v_sid uuid := gen_random_uuid();
begin
  select u.user_id into v_uid from interno.usuarios_internos u where u.email = 'josegabrielpo422@gmail.com' and u.ativo;
  if v_uid is null then raise exception 'Usuário do painel josegabrielpo422@gmail.com não encontrado; reversão não aplicada.'; end if;
  insert into interno.sessoes_painel (session_id, user_id) values (v_sid, v_uid);
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated', 'email', 'josegabrielpo422@gmail.com', 'session_id', v_sid)::text, true);
  execute 'set local role authenticated';

  perform painel.salvar_cronograma_item(3, 'Período de inscrições (inclusive)', '2026-10-05'::date, '2026-10-20'::date, null,
    'Reversão para a minuta v9 (29/09/2026).');
  perform painel.salvar_cronograma_item(12, 'Habilitação documental e análise curricular (simultâneas)', '2026-10-29'::date, '2026-11-05'::date, null,
    'Reversão para a minuta v9 (29/09/2026).');
  perform painel.salvar_cronograma_item(13, 'Decisão dos recursos contra indeferimento de inscrição', null, '2026-11-05'::date, null,
    'Reversão para a minuta v9 (29/09/2026).');
  perform painel.salvar_cronograma_item(24, 'Homologação do resultado final', null, '2026-12-11'::date, null,
    'Reversão para a minuta v9 (29/09/2026).');

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end;
$$;
