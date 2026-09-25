-- Volta ao estado anterior à migração 20260925130000 (fichas lançadas pela Comissão com nome digitado).
-- Definições completas salvas antes da mudança.

drop function if exists painel.minhas_entrevistas();
drop function if exists painel.remover_minha_ficha(uuid, text);
drop function if exists painel.salvar_ficha_entrevista(uuid, jsonb, jsonb);

CREATE OR REPLACE FUNCTION painel.entrevista_do_candidato(p_inscricao_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ac numeric;
  v_n integer;
  v_et numeric;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  perform interno.recalcular_todas();
  select a.total into v_ac from interno.avaliacoes_curriculares a where a.inscricao_id = p_inscricao_id;
  select count(*), round(avg(f.total), 2) into v_n, v_et from interno.fichas_entrevista f where f.inscricao_id = p_inscricao_id;
  return jsonb_build_object(
    'convocado', interno.eh_convocado(p_inscricao_id),
    'ac', v_ac,
    'n_fichas', v_n,
    'et', v_et,
    'pf', case when v_et is null then null else v_ac + v_et end,
    'banca_completa', v_n >= 3,
    'abaixo_do_corte', v_et is not null and v_et < 15,
    'fichas', coalesce((
      select jsonb_agg(to_jsonb(f) - 'lancado_por' order by f.created_at)
      from interno.fichas_entrevista f where f.inscricao_id = p_inscricao_id), '[]'::jsonb)
  );
end;
$function$

;

CREATE OR REPLACE FUNCTION painel.salvar_ficha_entrevista(p_inscricao_id uuid, p_avaliador text, p_notas jsonb, p_justificativas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  k text;
  ks constant text[] := array['dominio', 'analise', 'planejamento', 'comunicacao', 'caso', 'postura'];
  teto constant integer[] := array[10, 10, 5, 5, 5, 5];
  v integer;
  j text;
  i integer;
  f interno.fichas_entrevista;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  perform interno.recalcular_todas();
  if not interno.eh_convocado(p_inscricao_id) then
    raise exception 'Só candidatos convocados para a entrevista (AC ≥ 35 e dentro de 3 por vaga) recebem ficha.' using errcode = 'P0001', hint = 'nao_convocado';
  end if;
  if char_length(btrim(coalesce(p_avaliador, ''))) < 3 then
    raise exception 'Informe o nome do avaliador.' using errcode = 'P0001', hint = 'avaliador_obrigatorio';
  end if;
  for i in 1..6 loop
    k := ks[i];
    begin v := (p_notas ->> k)::integer; exception when others then v := null; end;
    if v is null or v < 0 or v > teto[i] then
      raise exception 'Nota de "%" inválida: use um número inteiro de 0 a %.', k, teto[i] using errcode = 'P0001', hint = 'nota_invalida';
    end if;
    j := btrim(coalesce(p_justificativas ->> k, ''));
    if char_length(j) < 3 then
      raise exception 'Justificativa obrigatória para "%".', k using errcode = 'P0001', hint = 'justificativa_obrigatoria';
    end if;
  end loop;

  insert into interno.fichas_entrevista as x (
    inscricao_id, avaliador_nome,
    nota_dominio, nota_analise, nota_planejamento, nota_comunicacao, nota_caso, nota_postura,
    just_dominio, just_analise, just_planejamento, just_comunicacao, just_caso, just_postura, lancado_por)
  values (
    p_inscricao_id, btrim(p_avaliador),
    (p_notas ->> 'dominio')::int, (p_notas ->> 'analise')::int, (p_notas ->> 'planejamento')::int,
    (p_notas ->> 'comunicacao')::int, (p_notas ->> 'caso')::int, (p_notas ->> 'postura')::int,
    btrim(p_justificativas ->> 'dominio'), btrim(p_justificativas ->> 'analise'), btrim(p_justificativas ->> 'planejamento'),
    btrim(p_justificativas ->> 'comunicacao'), btrim(p_justificativas ->> 'caso'), btrim(p_justificativas ->> 'postura'),
    auth.uid())
  on conflict (inscricao_id, avaliador_nome) do update set
    nota_dominio = excluded.nota_dominio, nota_analise = excluded.nota_analise, nota_planejamento = excluded.nota_planejamento,
    nota_comunicacao = excluded.nota_comunicacao, nota_caso = excluded.nota_caso, nota_postura = excluded.nota_postura,
    just_dominio = excluded.just_dominio, just_analise = excluded.just_analise, just_planejamento = excluded.just_planejamento,
    just_comunicacao = excluded.just_comunicacao, just_caso = excluded.just_caso, just_postura = excluded.just_postura,
    lancado_por = auth.uid(), updated_at = now()
  returning * into f;
  return to_jsonb(f) - 'lancado_por';
end;
$function$

;

CREATE OR REPLACE FUNCTION painel.remover_ficha_entrevista(p_ficha_id uuid, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 5 then
    raise exception 'Informe o motivo da remoção (mín. 5 caracteres).' using errcode = 'P0001', hint = 'motivo_obrigatorio';
  end if;
  insert into interno.auditoria (ator_id, ator_role, acao, entidade, entidade_id, dados_depois)
  values (auth.uid(), 'authenticated', 'MOTIVO_REMOCAO_FICHA', 'interno.fichas_entrevista', p_ficha_id::text,
          jsonb_build_object('motivo', btrim(p_motivo)));
  delete from interno.fichas_entrevista where id = p_ficha_id;
end;
$function$

;

CREATE OR REPLACE FUNCTION painel.classificacao_final(p_grupo publico.grupo_vaga DEFAULT NULL::publico.grupo_vaga, p_nivel publico.nivel_vaga DEFAULT NULL::publico.nivel_vaga)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ref date := (interno.encerramento() at time zone 'America/Sao_Paulo')::date;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  perform interno.recalcular_todas();
  return query
    with base as (
      select i.id as insc, c.nome, c.cpf, i.grupo, i.nivel, a.total as ac, a.pontos_experiencia as exp,
             i.data_colacao as colacao, c.data_nascimento as nasc,
             (extract(year from age(ref, c.data_nascimento)) >= 60) as idoso,
             (select count(*) from interno.fichas_entrevista f where f.inscricao_id = i.id) as n_fichas,
             (select round(avg(f.total), 2) from interno.fichas_entrevista f where f.inscricao_id = i.id) as et
      from publico.inscricoes i
      join publico.candidatos c on c.id = i.candidato_id
      join interno.avaliacoes_curriculares a on a.inscricao_id = i.id
      where interno.eh_convocado(i.id)
        and (p_grupo is null or i.grupo = p_grupo) and (p_nivel is null or i.nivel = p_nivel)
    ),
    calc as (
      select b.*, (b.ac + b.et) as pf, (b.et is not null and b.et < 15) as abaixo_corte
      from base b
    ),
    ranqueados as (
      select k.insc,
             rank() over (
               partition by k.grupo, k.nivel
               order by k.pf desc, k.idoso desc, case when k.idoso then k.nasc end asc,
                        k.et desc, k.exp desc, k.ac desc, k.colacao asc, k.nasc asc
             )::integer as posicao
      from calc k where k.et is not null and not k.abaixo_corte
    )
    select jsonb_build_object(
      'inscricao_id', k.insc, 'nome', k.nome, 'cpf', k.cpf, 'grupo', k.grupo, 'nivel', k.nivel,
      'ac', k.ac, 'et', k.et, 'pf', k.pf, 'n_fichas', k.n_fichas, 'banca_completa', k.n_fichas >= 3,
      'abaixo_do_corte', k.abaixo_corte, 'posicao', r.posicao)
    from calc k left join ranqueados r on r.insc = k.insc
    order by k.grupo, k.nivel, r.posicao nulls last, k.pf desc nulls last, k.nome;
end;
$function$

;

CREATE OR REPLACE FUNCTION painel.listar_usuarios_painel()
 RETURNS TABLE(user_id uuid, nome text, email text, perfil text, ativo boolean, cpf_mascarado text, senha_definida boolean, bloqueado_ate timestamp with time zone, ultimo_acesso timestamp with time zone, qtd_fichas integer, avaliados jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    select u.user_id, u.nome, u.email, u.perfil, u.ativo,
           case when u.cpf is null then null else '***.***.***-' || right(u.cpf, 2) end,
           u.senha_hash is not null,
           case when u.bloqueado_ate > now() then u.bloqueado_ate end,
           (select max(s.criada_em) from interno.sessoes_painel s where s.user_id = u.user_id),
           (select count(*)::integer from interno.fichas_entrevista f where f.lancado_por = u.user_id),
           coalesce((
             select jsonb_agg(jsonb_build_object(
                      'inscricao_id', f.inscricao_id, 'candidato', c.nome, 'grupo', i.grupo, 'nivel', i.nivel,
                      'avaliador_informado', f.avaliador_nome, 'total', f.total, 'lancada_em', f.created_at)
                    order by f.created_at desc)
             from interno.fichas_entrevista f
             join publico.inscricoes i on i.id = f.inscricao_id
             join publico.candidatos c on c.id = i.candidato_id
             where f.lancado_por = u.user_id
           ), '[]'::jsonb)
    from interno.usuarios_internos u
    order by u.ativo desc, u.nome;
end;
$function$

;

revoke execute on function painel.salvar_ficha_entrevista(uuid, text, jsonb, jsonb), painel.remover_ficha_entrevista(uuid, text) from public, anon;
grant execute on function painel.salvar_ficha_entrevista(uuid, text, jsonb, jsonb), painel.remover_ficha_entrevista(uuid, text) to authenticated;
drop function if exists interno.media_entrevista(uuid);
alter table interno.fichas_entrevista drop constraint fichas_entrevista_um_por_avaliador;
alter table interno.fichas_entrevista add constraint fichas_entrevista_inscricao_id_avaliador_nome_key unique (inscricao_id, avaliador_nome);
alter table interno.fichas_entrevista drop column avaliador_id;
