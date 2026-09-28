-- Entrevista técnica: link da gravação da reunião (interno, nunca mostrado ao candidato; edital 6.5.6) e FINALIZAÇÃO do
-- registro do candidato pela Comissão, depois das fichas da banca (mínimo de 3 avaliadores, 6.5.2).
--   * presenca_entrevista.link_gravacao (opcional, http/https): guardado junto com a observação; só o painel enxerga;
--   * interno.entrevista_finalizada: um registro por candidato (autor, data); depois de finalizado NÃO se registra presença
--     nem se lança/remove ficha (só reabertura direta no banco, por administrador);
--   * painel.finalizar_entrevista(): exige presença "realizada" e >= 3 fichas;
--   * o candidato passa a ver "Avaliação técnica finalizada" (publico.minha_presenca_entrevista().finalizada), sem nota, sem
--     observação e sem link.
-- Reversão: supabase/rollback/20260928110000_presenca_gravacao_e_finalizacao.down.sql

alter table interno.presenca_entrevista
  add column link_gravacao text check (link_gravacao is null or (link_gravacao ~* '^https?://[^\s]+$' and char_length(link_gravacao) <= 500));

create table interno.entrevista_finalizada (
  inscricao_id   uuid primary key references publico.inscricoes (id),
  finalizado_por uuid not null,
  finalizado_em  timestamptz not null default clock_timestamp()
);
alter table interno.entrevista_finalizada enable row level security;
revoke all on interno.entrevista_finalizada from public, anon, authenticated;
create trigger entrevista_finalizada_auditoria after insert or update or delete on interno.entrevista_finalizada
  for each row execute function interno.registrar_auditoria();

create or replace function interno.entrevista_esta_finalizada(p_inscricao_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from interno.entrevista_finalizada f where f.inscricao_id = p_inscricao_id) $$;
revoke execute on function interno.entrevista_esta_finalizada(uuid) from public, anon, authenticated;

------------------------------------------------------------------------------
-- Presença: agora com o link da gravação; bloqueada depois de finalizado
------------------------------------------------------------------------------
drop function painel.registrar_presenca_entrevista(uuid, text, text);
create function painel.registrar_presenca_entrevista(p_inscricao_id uuid, p_situacao text, p_observacao text default null, p_link_gravacao text default null)
returns interno.presenca_entrevista
language plpgsql security definer set search_path = ''
as $$
declare
  r interno.presenca_entrevista;
  v_link text := nullif(btrim(coalesce(p_link_gravacao, '')), '');
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
  insert into interno.presenca_entrevista (inscricao_id, situacao, observacao, link_gravacao, registrado_por)
  values (p_inscricao_id, p_situacao, nullif(btrim(coalesce(p_observacao, '')), ''), v_link, auth.uid())
  returning * into r;
  return r;
end;
$$;

drop function painel.presenca_entrevista_do_candidato(uuid);
create function painel.presenca_entrevista_do_candidato(p_inscricao_id uuid)
returns table (situacao text, observacao text, link_gravacao text, registrado_por_nome text, registrado_em timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select p.situacao, p.observacao, p.link_gravacao, coalesce(u.nome, '—'), p.registrado_em
    from interno.presenca_entrevista p
    left join interno.usuarios_internos u on u.user_id = p.registrado_por
    where p.inscricao_id = p_inscricao_id
    order by p.registrado_em desc;
end;
$$;

------------------------------------------------------------------------------
-- Finalizar o registro do candidato
------------------------------------------------------------------------------
create or replace function painel.finalizar_entrevista(p_inscricao_id uuid)
returns interno.entrevista_finalizada
language plpgsql security definer set search_path = ''
as $$
declare r interno.entrevista_finalizada;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  perform interno.recalcular_todas();
  if not interno.eh_convocado(p_inscricao_id) then
    raise exception 'Só candidatos convocados para a entrevista podem ter o registro finalizado.' using errcode = 'P0001', hint = 'nao_convocado';
  end if;
  if interno.entrevista_esta_finalizada(p_inscricao_id) then
    raise exception 'O registro deste candidato já foi finalizado.' using errcode = 'P0001', hint = 'entrevista_finalizada';
  end if;
  if interno.presenca_entrevista_atual(p_inscricao_id) is distinct from 'realizada' then
    raise exception 'Registre que o candidato compareceu à entrevista antes de finalizar.' using errcode = 'P0001', hint = 'sem_presenca';
  end if;
  if (select count(*) from interno.fichas_entrevista f where f.inscricao_id = p_inscricao_id) < 3 then
    raise exception 'A banca precisa ter lançado pelo menos 3 fichas (item 6.5.2) para finalizar.' using errcode = 'P0001', hint = 'faltam_fichas';
  end if;
  insert into interno.entrevista_finalizada (inscricao_id, finalizado_por) values (p_inscricao_id, auth.uid())
  returning * into r;
  return r;
end;
$$;

create or replace function painel.entrevista_finalizacao(p_inscricao_id uuid)
returns table (finalizado_em timestamptz, finalizado_por_nome text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select f.finalizado_em, coalesce(u.nome, '—')
    from interno.entrevista_finalizada f
    left join interno.usuarios_internos u on u.user_id = f.finalizado_por
    where f.inscricao_id = p_inscricao_id;
end;
$$;

------------------------------------------------------------------------------
-- Candidato: só a situação (e se o registro foi finalizado). Nada de observação nem link.
------------------------------------------------------------------------------
drop function publico.minha_presenca_entrevista();
create function publico.minha_presenca_entrevista()
returns table (situacao text, registrado_em timestamptz, finalizada boolean)
language sql stable security definer set search_path = ''
as $$
  select p.situacao, p.registrado_em, interno.entrevista_esta_finalizada(p.inscricao_id)
  from interno.presenca_entrevista p
  where p.inscricao_id = (select publico.minha_inscricao_id())
  order by p.registrado_em desc
  limit 1
$$;

revoke execute on function painel.registrar_presenca_entrevista(uuid, text, text, text), painel.presenca_entrevista_do_candidato(uuid),
  painel.finalizar_entrevista(uuid), painel.entrevista_finalizacao(uuid), publico.minha_presenca_entrevista() from public, anon;
grant execute on function painel.registrar_presenca_entrevista(uuid, text, text, text), painel.presenca_entrevista_do_candidato(uuid),
  painel.finalizar_entrevista(uuid), painel.entrevista_finalizacao(uuid), publico.minha_presenca_entrevista() to authenticated;

------------------------------------------------------------------------------
-- Depois de finalizado, não se lança nem se remove ficha (troca de texto simples; erro se o trecho não existir)
------------------------------------------------------------------------------
do $$
declare
  d text;
  ancora constant text := $t$  if interno.presenca_entrevista_atual(p_inscricao_id) = 'nao_compareceu' then$t$;
  novo constant text := $t$  if interno.entrevista_esta_finalizada(p_inscricao_id) then
    raise exception 'O registro deste candidato já foi finalizado; não é possível alterar fichas.' using errcode = 'P0001', hint = 'entrevista_finalizada';
  end if;
$t$ || ancora;
begin
  d := pg_get_functiondef('painel.salvar_ficha_entrevista(uuid,jsonb,jsonb)'::regprocedure);
  if position(ancora in d) = 0 then raise exception 'salvar_ficha_entrevista: trecho não encontrado'; end if;
  execute replace(d, ancora, novo);
end;
$$;

do $$
declare
  d text;
  ancora constant text := $t$  if char_length(btrim(coalesce(p_motivo, ''))) < 5 then$t$;
  novo constant text := $t$  if interno.entrevista_esta_finalizada(p_inscricao_id) then
    raise exception 'O registro deste candidato já foi finalizado; não é possível remover fichas.' using errcode = 'P0001', hint = 'entrevista_finalizada';
  end if;
$t$ || ancora;
begin
  d := pg_get_functiondef('painel.remover_minha_ficha(uuid,text)'::regprocedure);
  if position(ancora in d) = 0 then raise exception 'remover_minha_ficha: trecho não encontrado'; end if;
  execute replace(d, ancora, novo);
end;
$$;
