-- Registro de recursos (Capítulo IX do edital, item 9.1 a 9.2): os recursos chegam exclusivamente por
-- e-mail (9.2; resolve N9c — não há tela de recurso no portal), mas a Comissão precisa de um lugar para
-- registrar o que recebeu e a decisão fundamentada (itens 1.5, 1.6). Cabem recursos contra: indeferimento
-- de isenção, indeferimento de inscrição, resultado preliminar de habilitação/AC, resultado preliminar da
-- entrevista, resultado de reservas de vagas e resultado preliminar final (item 9.1, alíneas a-f).
-- Fica em `interno` (não no schema `publico`): o candidato não acompanha o recurso pela plataforma, só por
-- e-mail, como o próprio edital manda.
create table interno.recursos (
  id uuid primary key default gen_random_uuid(),
  inscricao_id uuid not null references publico.inscricoes(id),
  etapa text not null check (etapa in ('isencao', 'inscricao', 'ac', 'entrevista', 'reservas_vagas', 'resultado_final')),
  recebido_em date not null,
  fundamentacao text not null,
  decisao text not null default 'pendente' check (decisao in ('pendente', 'deferido', 'indeferido')),
  decisao_motivada text,
  decidido_por uuid references interno.usuarios_internos(user_id),
  decidido_em timestamptz,
  registrado_por uuid not null references interno.usuarios_internos(user_id),
  created_at timestamptz not null default now()
);

alter table interno.recursos enable row level security;
-- Sem políticas: só acessível via as funções SECURITY DEFINER abaixo (padrão de interno.decisoes_inscricao).

-- Registra um recurso recebido por e-mail. p_etapa: contra qual decisão o recurso é dirigido (item 9.1).
create or replace function painel.registrar_recurso(p_inscricao_id uuid, p_etapa text, p_recebido_em date, p_fundamentacao text)
returns interno.recursos
language plpgsql
security definer
set search_path to ''
as $$
declare
  r interno.recursos;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if p_etapa not in ('isencao', 'inscricao', 'ac', 'entrevista', 'reservas_vagas', 'resultado_final') then
    raise exception 'Etapa inválida.' using errcode = 'P0001', hint = 'etapa_invalida';
  end if;
  if not exists (select 1 from publico.inscricoes where id = p_inscricao_id) then
    raise exception 'Inscrição não encontrada.' using errcode = 'P0001', hint = 'nao_encontrada';
  end if;
  if char_length(btrim(coalesce(p_fundamentacao, ''))) < 5 then
    raise exception 'Informe a fundamentação do recurso (mínimo de 5 caracteres).' using errcode = 'P0001', hint = 'fundamentacao_obrigatoria';
  end if;
  if p_recebido_em is null then
    raise exception 'Informe a data de recebimento do recurso.' using errcode = 'P0001', hint = 'data_obrigatoria';
  end if;

  insert into interno.recursos (inscricao_id, etapa, recebido_em, fundamentacao, registrado_por)
  values (p_inscricao_id, p_etapa, p_recebido_em, btrim(p_fundamentacao), auth.uid())
  returning * into r;

  insert into interno.auditoria (ator_id, ator_role, acao, entidade, entidade_id, dados_depois)
  values (auth.uid(), 'authenticated', 'REGISTRAR_RECURSO', 'interno.recursos', r.id::text,
          jsonb_build_object('inscricao_id', p_inscricao_id, 'etapa', p_etapa, 'recebido_em', p_recebido_em));
  return r;
end;
$$;

-- Decide um recurso já registrado, com motivação sempre obrigatória (itens 1.5 e 1.6: nenhuma decisão sem
-- fundamentação). Quando o recurso é contra o indeferimento da INSCRIÇÃO e é deferido, a inscrição volta a
-- 'homologada' para seguir "nas mesmas condições dos demais candidatos" (item 4.13, minuta v11).
create or replace function painel.decidir_recurso(p_recurso_id uuid, p_deferido boolean, p_motivo text)
returns interno.recursos
language plpgsql
security definer
set search_path to ''
as $$
declare
  r interno.recursos;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'Informe o motivo da decisão (mínimo de 10 caracteres).' using errcode = 'P0001', hint = 'motivo_obrigatorio';
  end if;

  update interno.recursos
     set decisao = case when p_deferido then 'deferido' else 'indeferido' end,
         decisao_motivada = btrim(p_motivo), decidido_por = auth.uid(), decidido_em = now()
   where id = p_recurso_id
   returning * into r;
  if not found then
    raise exception 'Recurso não encontrado.' using errcode = 'P0001', hint = 'nao_encontrado';
  end if;

  if r.etapa = 'inscricao' and p_deferido then
    perform set_config('pss.decisao_comissao', 'on', true);
    update publico.inscricoes set status = 'homologada' where id = r.inscricao_id and status = 'indeferida';
    perform set_config('pss.decisao_comissao', 'off', true);
  end if;

  insert into interno.auditoria (ator_id, ator_role, acao, entidade, entidade_id, dados_depois)
  values (auth.uid(), 'authenticated', 'DECIDIR_RECURSO', 'interno.recursos', r.id::text,
          jsonb_build_object('decisao', r.decisao, 'motivo', btrim(p_motivo)));
  return r;
end;
$$;

-- Lista os recursos para a tela da Comissão, com os dados do candidato.
create or replace function painel.listar_recursos()
returns table(
  id uuid, inscricao_id uuid, nome text, cpf text, grupo publico.grupo_vaga, nivel publico.nivel_vaga,
  etapa text, recebido_em date, fundamentacao text, decisao text, decisao_motivada text,
  decidido_em timestamptz, decidido_por text, registrado_em timestamptz, registrado_por text
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
    select r.id, r.inscricao_id, c.nome, c.cpf, i.grupo, i.nivel, r.etapa, r.recebido_em, r.fundamentacao,
           r.decisao, r.decisao_motivada, r.decidido_em, ud.nome, r.created_at, ur.nome
    from interno.recursos r
    join publico.inscricoes i on i.id = r.inscricao_id
    join publico.candidatos c on c.id = i.candidato_id
    left join interno.usuarios_internos ud on ud.user_id = r.decidido_por
    join interno.usuarios_internos ur on ur.user_id = r.registrado_por
    order by r.created_at desc;
end;
$$;
