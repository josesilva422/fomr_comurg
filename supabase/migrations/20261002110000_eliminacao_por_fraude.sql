-- Eliminação por fraude ou falsidade documental (itens 5.5.4 e 14.3): "eliminação imediata e comunicação
-- às autoridades"; decisão EXCLUSIVAMENTE humana (o sistema/IA só sinaliza indícios na extração, nunca
-- decide). Usa o status 'cancelada', já previsto em publico.status_inscricao e até aqui sem uso (a
-- divergência do Pix, item 4.9.4, segue pela homologação/rejeição, não por cancelamento automático —
-- decisão pendente 15). Guarda o status anterior para permitir reverter uma decisão equivocada, com
-- motivo e auditoria nos dois sentidos.
create table interno.eliminacoes (
  id uuid primary key default gen_random_uuid(),
  inscricao_id uuid not null references publico.inscricoes(id),
  status_anterior publico.status_inscricao not null,
  motivo text not null,
  decidido_por uuid not null references interno.usuarios_internos(user_id),
  decidido_em timestamptz not null default now(),
  revertido_em timestamptz,
  revertido_por uuid references interno.usuarios_internos(user_id),
  motivo_reversao text
);

alter table interno.eliminacoes enable row level security;
-- Sem políticas: só acessível via as funções SECURITY DEFINER abaixo (padrão de interno.recursos).

-- Elimina a inscrição por fraude/falsidade. Exige justificativa robusta (itens 1.5, 1.6: nenhuma
-- eliminação sem decisão fundamentada) e nunca decide por si: quem chama é sempre um humano da Comissão.
create or replace function painel.eliminar_por_fraude(p_inscricao_id uuid, p_motivo text)
returns interno.eliminacoes
language plpgsql
security definer
set search_path to ''
as $$
declare r interno.eliminacoes; v_status publico.status_inscricao;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 20 then
    raise exception 'Justifique a eliminação com o indício de fraude ou falsidade constatado (mínimo de 20 caracteres, itens 5.5.4 e 14.3).'
      using errcode = 'P0001', hint = 'motivo_obrigatorio';
  end if;
  select status into v_status from publico.inscricoes where id = p_inscricao_id;
  if v_status is null then
    raise exception 'Inscrição não encontrada.' using errcode = 'P0001', hint = 'nao_encontrada';
  end if;
  if v_status = 'cancelada' then
    raise exception 'Esta inscrição já está cancelada.' using errcode = 'P0001', hint = 'ja_cancelada';
  end if;

  insert into interno.eliminacoes (inscricao_id, status_anterior, motivo, decidido_por)
  values (p_inscricao_id, v_status, btrim(p_motivo), auth.uid())
  returning * into r;

  perform set_config('pss.decisao_comissao', 'on', true);
  update publico.inscricoes set status = 'cancelada' where id = p_inscricao_id;
  perform set_config('pss.decisao_comissao', 'off', true);

  insert into interno.auditoria (ator_id, ator_role, acao, entidade, entidade_id, dados_depois)
  values (auth.uid(), 'authenticated', 'ELIMINAR_POR_FRAUDE', 'publico.inscricoes', p_inscricao_id::text,
          jsonb_build_object('status_anterior', v_status, 'motivo', btrim(p_motivo)));
  return r;
end;
$$;

-- Reverte uma eliminação decidida por engano (ex.: apuração posterior afastou o indício). Volta ao status
-- anterior exato e marca a linha de interno.eliminacoes como revertida (nunca apaga o histórico).
create or replace function painel.reverter_eliminacao(p_inscricao_id uuid, p_motivo text)
returns interno.eliminacoes
language plpgsql
security definer
set search_path to ''
as $$
declare r interno.eliminacoes;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'Informe o motivo da reversão (mínimo de 10 caracteres).' using errcode = 'P0001', hint = 'motivo_obrigatorio';
  end if;

  select * into r from interno.eliminacoes
   where inscricao_id = p_inscricao_id and revertido_em is null
   order by decidido_em desc limit 1;
  if r.id is null then
    raise exception 'Não há eliminação ativa para reverter nesta inscrição.' using errcode = 'P0001', hint = 'nao_encontrada';
  end if;

  update interno.eliminacoes
     set revertido_em = now(), revertido_por = auth.uid(), motivo_reversao = btrim(p_motivo)
   where id = r.id
   returning * into r;

  perform set_config('pss.decisao_comissao', 'on', true);
  update publico.inscricoes set status = r.status_anterior where id = p_inscricao_id;
  perform set_config('pss.decisao_comissao', 'off', true);

  insert into interno.auditoria (ator_id, ator_role, acao, entidade, entidade_id, dados_depois)
  values (auth.uid(), 'authenticated', 'REVERTER_ELIMINACAO', 'publico.inscricoes', p_inscricao_id::text,
          jsonb_build_object('status_restaurado', r.status_anterior, 'motivo', btrim(p_motivo)));
  return r;
end;
$$;

-- Lista as eliminações (ativas e revertidas) para a tela da Comissão.
create or replace function painel.listar_eliminacoes()
returns table(
  id uuid, inscricao_id uuid, nome text, cpf text, status_anterior publico.status_inscricao,
  motivo text, decidido_em timestamptz, decidido_por text,
  revertido_em timestamptz, revertido_por text, motivo_reversao text
)
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select e.id, e.inscricao_id, c.nome, c.cpf, e.status_anterior, e.motivo, e.decidido_em, ud.nome,
           e.revertido_em, ur.nome, e.motivo_reversao
    from interno.eliminacoes e
    join publico.inscricoes i on i.id = e.inscricao_id
    join publico.candidatos c on c.id = i.candidato_id
    join interno.usuarios_internos ud on ud.user_id = e.decidido_por
    left join interno.usuarios_internos ur on ur.user_id = e.revertido_por
    order by e.decidido_em desc;
end;
$$;
