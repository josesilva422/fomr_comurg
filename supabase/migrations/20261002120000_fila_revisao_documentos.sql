-- Fila de revisão da Comissão com IA (CLAUDE.md, seção 12, Fase 2: "fila de revisão da Comissão, com
-- documento ao lado dos dados extraídos"). Até aqui a extração por IA só existia por documento, um a um,
-- dentro da página de cada candidato (painel.registrar_extracao, acionada por /api/extrair-documento); não
-- havia lista entre candidatos do que falta revisar, nem como marcar uma extração como revisada/corrigida
-- (o status da tabela interno.extracoes ficava sempre em 'pendente', sem uso).
alter table interno.extracoes add column if not exists revisado_em timestamptz;
alter table interno.extracoes add column if not exists observacao_revisao text;

-- Marca uma extração como revisada (confirmada) ou corrigida (a Comissão identificou erro da IA), com uma
-- observação opcional. Não é uma decisão do processo (habilitação, pontuação, eliminação) — é só o
-- registro de que um humano confrontou o documento com a extração, conforme a seção 2 do CLAUDE.md
-- ("a IA nunca decide sozinha").
create or replace function painel.revisar_extracao(p_extracao_id uuid, p_status text, p_observacao text default null)
returns interno.extracoes
language plpgsql
security definer
set search_path to ''
as $$
declare r interno.extracoes;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if p_status not in ('revisada', 'corrigida') then
    raise exception 'Status inválido.' using errcode = 'P0001', hint = 'status_invalido';
  end if;

  update interno.extracoes
     set status = p_status, revisado_por = auth.uid(), revisado_em = now(),
         observacao_revisao = nullif(btrim(coalesce(p_observacao, '')), '')
   where id = p_extracao_id
   returning * into r;
  if not found then
    raise exception 'Extração não encontrada.' using errcode = 'P0001', hint = 'nao_encontrada';
  end if;

  insert into interno.auditoria (ator_id, ator_role, acao, entidade, entidade_id, dados_depois)
  values (auth.uid(), 'authenticated', 'REVISAR_EXTRACAO', 'interno.extracoes', p_extracao_id::text,
          jsonb_build_object('status', p_status, 'observacao', nullif(btrim(coalesce(p_observacao, '')), '')));
  return r;
end;
$$;

-- Fila entre candidatos: um documento por linha, com a última extração (se houver) ao lado. p_status:
-- 'pendente' (padrão) traz o que falta revisar — extraído e ainda não revisado, OU nunca extraído;
-- 'revisada'/'corrigida' filtra pelo status da extração; 'todas' não filtra.
create or replace function painel.listar_fila_revisao(p_status text default 'pendente')
returns table(
  documento_id uuid, inscricao_id uuid, nome text, cpf text, grupo publico.grupo_vaga, nivel publico.nivel_vaga,
  tipo publico.tipo_documento, enviado_em timestamptz,
  extracao_id uuid, status text, confianca numeric, legivel boolean, suspeita_adulteracao boolean,
  tipo_bate boolean, qtd_nao_confere integer, resumo text, revisado_em timestamptz, revisado_por text
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
    with ultima as (
      select e.*, row_number() over (partition by e.documento_id order by e.criado_em desc) as rn
      from interno.extracoes e
    )
    select d.id, d.inscricao_id, c.nome, c.cpf, i.grupo, i.nivel, d.tipo, d.enviado_em,
           u.id, coalesce(u.status, 'sem_extracao'), u.confianca,
           (u.json_extraido ->> 'legivel')::boolean,
           (u.json_extraido #> '{indicios_adulteracao,suspeita}')::boolean,
           (u.json_extraido #> '{tipo_documento,bate_com_esperado}')::boolean,
           (select count(*)::integer from jsonb_array_elements(coalesce(u.json_extraido -> 'comparacoes', '[]'::jsonb)) x
             where x ->> 'confere' = 'nao'),
           u.json_extraido ->> 'resumo_documento', u.revisado_em, ur.nome
    from publico.documentos d
    join publico.inscricoes i on i.id = d.inscricao_id
    join publico.candidatos c on c.id = i.candidato_id
    left join ultima u on u.documento_id = d.id and u.rn = 1
    left join interno.usuarios_internos ur on ur.user_id = u.revisado_por
    where d.ativo and i.status <> 'rascunho'
      and (
        p_status = 'todas'
        or (p_status = 'pendente' and (u.id is null or u.status = 'pendente'))
        or (p_status <> 'pendente' and u.status = p_status)
      )
    order by (u.json_extraido #> '{indicios_adulteracao,suspeita}') = 'true'::jsonb desc nulls last,
             u.confianca asc nulls first, d.enviado_em;
end;
$$;
