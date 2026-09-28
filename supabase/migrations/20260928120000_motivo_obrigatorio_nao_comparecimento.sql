-- Não comparecimento à entrevista (item 6.5.7) elimina o candidato: a decisão da Comissão exige MOTIVO registrado
-- (itens 1.5 e 1.6). Passa a ser obrigatório (mín. 5 caracteres) no banco, não só na tela. "Compareceu" segue com observação
-- opcional. Mesma função de 20260928110000, com a nova checagem antes da gravação.
-- Reversão: reaplicar painel.registrar_presenca_entrevista de 20260928110000_presenca_gravacao_e_finalizacao.sql

create or replace function painel.registrar_presenca_entrevista(p_inscricao_id uuid, p_situacao text, p_observacao text default null, p_link_gravacao text default null)
returns interno.presenca_entrevista
language plpgsql security definer set search_path = ''
as $$
declare
  r interno.presenca_entrevista;
  v_link text := nullif(btrim(coalesce(p_link_gravacao, '')), '');
  v_obs text := nullif(btrim(coalesce(p_observacao, '')), '');
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if p_situacao not in ('realizada', 'nao_compareceu') then
    raise exception 'Situação inválida.' using errcode = 'P0001', hint = 'situacao_invalida';
  end if;
  if v_link is not null and (v_link !~* '^https?://[^\s]+$' or char_length(v_link) > 500) then
    raise exception 'O link da gravação precisa começar com http:// ou https://.' using errcode = 'P0001', hint = 'link_invalido';
  end if;
  perform interno.recalcular_todas();
  if not interno.eh_convocado(p_inscricao_id) then
    raise exception 'Só candidatos convocados para a entrevista têm presença registrada.' using errcode = 'P0001', hint = 'nao_convocado';
  end if;
  if interno.entrevista_esta_finalizada(p_inscricao_id) then
    raise exception 'O registro deste candidato já foi finalizado.' using errcode = 'P0001', hint = 'entrevista_finalizada';
  end if;
  if not exists (select 1 from interno.convites_entrevista c where c.inscricao_id = p_inscricao_id) then
    raise exception 'Registre o convite da entrevista antes de informar a presença.' using errcode = 'P0001', hint = 'sem_convite';
  end if;
  if p_situacao = 'nao_compareceu'
     and exists (select 1 from interno.fichas_entrevista f where f.inscricao_id = p_inscricao_id) then
    raise exception 'Este candidato já tem ficha de avaliador; não é possível registrar ausência.' using errcode = 'P0001', hint = 'ja_tem_ficha';
  end if;
  if p_situacao = 'nao_compareceu' and char_length(coalesce(v_obs, '')) < 5 then
    raise exception 'Informe o motivo do não comparecimento (mínimo de 5 caracteres).' using errcode = 'P0001', hint = 'motivo_obrigatorio';
  end if;
  insert into interno.presenca_entrevista (inscricao_id, situacao, observacao, link_gravacao, registrado_por)
  values (p_inscricao_id, p_situacao, v_obs, v_link, auth.uid())
  returning * into r;
  return r;
end;
$$;
revoke execute on function painel.registrar_presenca_entrevista(uuid, text, text, text) from public, anon;
grant execute on function painel.registrar_presenca_entrevista(uuid, text, text, text) to authenticated;
