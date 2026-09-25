-- Entrevista técnica: fichas CEGAS por avaliador (pedido do responsável, 25/09/2026; edital 6.5.5: "cada avaliador
-- atribuirá sua nota individualmente"; Anexo II, Parte 2).
--
--   * Cada ficha pertence ao LOGIN do avaliador (avaliador_id = auth.uid()); uma ficha por avaliador por candidato.
--     O nome vem do cadastro do usuário do painel (interno.usuarios_internos), não é mais digitado.
--   * Ninguém vê a nota de outro avaliador. Cada um vê e corrige só a própria ficha.
--   * Com MENOS de 3 fichas (banca mínima, 6.5.2) não aparece média nenhuma. A partir de 3, aparece a MÉDIA das fichas
--     enviadas (ET, 6.5.5), a média por competência e a PF = AC + ET. As notas individuais continuam não aparecendo.
--   * No máximo 10 fichas por candidato.
--   * A tela "Usuários do painel" deixa de mostrar o total de cada ficha (vazava a nota individual).
-- Reversão: supabase/rollback/20260925130000_entrevista_fichas_por_avaliador.down.sql

alter table interno.fichas_entrevista add column avaliador_id uuid;
update interno.fichas_entrevista set avaliador_id = lancado_por where avaliador_id is null;
alter table interno.fichas_entrevista alter column avaliador_id set not null;
alter table interno.fichas_entrevista drop constraint fichas_entrevista_inscricao_id_avaliador_nome_key;
alter table interno.fichas_entrevista add constraint fichas_entrevista_um_por_avaliador unique (inscricao_id, avaliador_id);

------------------------------------------------------------------------------
-- ET só com banca mínima: média das fichas se houver 3 ou mais; senão, null (nada é mostrado).
------------------------------------------------------------------------------
create or replace function interno.media_entrevista(p_inscricao_id uuid) returns numeric
language sql stable security definer set search_path = ''
as $$
  select case when count(*) >= 3 then round(avg(f.total), 2) end
  from interno.fichas_entrevista f where f.inscricao_id = p_inscricao_id
$$;
revoke execute on function interno.media_entrevista(uuid) from public, anon, authenticated;

------------------------------------------------------------------------------
-- Visão geral de um candidato: quantas fichas, quem já enviou (sem nota), média só com 3+ e a PRÓPRIA ficha.
------------------------------------------------------------------------------
create or replace function painel.entrevista_do_candidato(p_inscricao_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_ac numeric;
  v_n integer;
  v_et numeric;
  v_liberada boolean;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  perform interno.recalcular_todas();
  select a.total into v_ac from interno.avaliacoes_curriculares a where a.inscricao_id = p_inscricao_id;
  select count(*) into v_n from interno.fichas_entrevista f where f.inscricao_id = p_inscricao_id;
  v_liberada := v_n >= 3;
  v_et := interno.media_entrevista(p_inscricao_id);
  return jsonb_build_object(
    'convocado', interno.eh_convocado(p_inscricao_id),
    'ac', v_ac,
    'n_fichas', v_n,
    'minimo_fichas', 3,
    'maximo_fichas', 10,
    'media_liberada', v_liberada,
    'et', v_et,
    'pf', case when v_et is null then null else v_ac + v_et end,
    'abaixo_do_corte', v_et is not null and v_et < 15,
    'media_por_competencia', case when v_liberada then (
      select jsonb_build_object(
        'dominio', round(avg(f.nota_dominio), 2), 'analise', round(avg(f.nota_analise), 2),
        'planejamento', round(avg(f.nota_planejamento), 2), 'comunicacao', round(avg(f.nota_comunicacao), 2),
        'caso', round(avg(f.nota_caso), 2), 'postura', round(avg(f.nota_postura), 2))
      from interno.fichas_entrevista f where f.inscricao_id = p_inscricao_id) end,
    -- quem já enviou, SEM nota (para a Comissão acompanhar a banca)
    'avaliadores', coalesce((
      select jsonb_agg(jsonb_build_object('nome', f.avaliador_nome, 'enviada_em', f.created_at) order by f.created_at)
      from interno.fichas_entrevista f where f.inscricao_id = p_inscricao_id), '[]'::jsonb),
    'minha_ficha', (
      select to_jsonb(f) - 'lancado_por' - 'avaliador_id'
      from interno.fichas_entrevista f where f.inscricao_id = p_inscricao_id and f.avaliador_id = auth.uid())
  );
end;
$$;

------------------------------------------------------------------------------
-- Página do avaliador: candidatos convocados e a situação da PRÓPRIA ficha em cada um.
------------------------------------------------------------------------------
create or replace function painel.minhas_entrevistas()
returns table (
  inscricao_id uuid, nome text, grupo publico.grupo_vaga, nivel publico.nivel_vaga,
  n_fichas integer, media_liberada boolean, minha_ficha_total smallint, minha_ficha_em timestamptz
)
language plpgsql security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  perform interno.recalcular_todas();
  return query
    select i.id, c.nome, i.grupo, i.nivel,
           (select count(*)::integer from interno.fichas_entrevista f where f.inscricao_id = i.id),
           (select count(*) >= 3 from interno.fichas_entrevista f where f.inscricao_id = i.id),
           m.total, m.updated_at
    from publico.inscricoes i
    join publico.candidatos c on c.id = i.candidato_id
    left join interno.fichas_entrevista m on m.inscricao_id = i.id and m.avaliador_id = auth.uid()
    where interno.eh_convocado(i.id)
    order by i.grupo, i.nivel, c.nome;
end;
$$;

------------------------------------------------------------------------------
-- Salva (ou corrige) a PRÓPRIA ficha do avaliador logado. Máximo de 10 fichas por candidato.
------------------------------------------------------------------------------
drop function painel.salvar_ficha_entrevista(uuid, text, jsonb, jsonb);
create function painel.salvar_ficha_entrevista(p_inscricao_id uuid, p_notas jsonb, p_justificativas jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  k text;
  ks constant text[] := array['dominio', 'analise', 'planejamento', 'comunicacao', 'caso', 'postura'];
  teto constant integer[] := array[10, 10, 5, 5, 5, 5];
  v integer;
  j text;
  i integer;
  v_nome text;
  f interno.fichas_entrevista;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  select u.nome into v_nome from interno.usuarios_internos u where u.user_id = auth.uid() and u.ativo;
  if char_length(btrim(coalesce(v_nome, ''))) < 3 then
    raise exception 'Seu usuário do painel está sem nome cadastrado; peça ao administrador para completar.' using errcode = 'P0001', hint = 'avaliador_sem_nome';
  end if;
  perform interno.recalcular_todas();
  if not interno.eh_convocado(p_inscricao_id) then
    raise exception 'Só candidatos convocados para a entrevista (AC ≥ 35 e dentro de 3 por vaga) recebem ficha.' using errcode = 'P0001', hint = 'nao_convocado';
  end if;
  if not exists (select 1 from interno.fichas_entrevista x where x.inscricao_id = p_inscricao_id and x.avaliador_id = auth.uid())
     and (select count(*) from interno.fichas_entrevista x where x.inscricao_id = p_inscricao_id) >= 10 then
    raise exception 'Este candidato já tem 10 fichas (limite).' using errcode = 'P0001', hint = 'limite_fichas';
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
    inscricao_id, avaliador_id, avaliador_nome,
    nota_dominio, nota_analise, nota_planejamento, nota_comunicacao, nota_caso, nota_postura,
    just_dominio, just_analise, just_planejamento, just_comunicacao, just_caso, just_postura, lancado_por)
  values (
    p_inscricao_id, auth.uid(), btrim(v_nome),
    (p_notas ->> 'dominio')::int, (p_notas ->> 'analise')::int, (p_notas ->> 'planejamento')::int,
    (p_notas ->> 'comunicacao')::int, (p_notas ->> 'caso')::int, (p_notas ->> 'postura')::int,
    btrim(p_justificativas ->> 'dominio'), btrim(p_justificativas ->> 'analise'), btrim(p_justificativas ->> 'planejamento'),
    btrim(p_justificativas ->> 'comunicacao'), btrim(p_justificativas ->> 'caso'), btrim(p_justificativas ->> 'postura'),
    auth.uid())
  on conflict (inscricao_id, avaliador_id) do update set
    avaliador_nome = excluded.avaliador_nome,
    nota_dominio = excluded.nota_dominio, nota_analise = excluded.nota_analise, nota_planejamento = excluded.nota_planejamento,
    nota_comunicacao = excluded.nota_comunicacao, nota_caso = excluded.nota_caso, nota_postura = excluded.nota_postura,
    just_dominio = excluded.just_dominio, just_analise = excluded.just_analise, just_planejamento = excluded.just_planejamento,
    just_comunicacao = excluded.just_comunicacao, just_caso = excluded.just_caso, just_postura = excluded.just_postura,
    lancado_por = auth.uid(), updated_at = now()
  returning * into f;
  return to_jsonb(f) - 'lancado_por' - 'avaliador_id';
end;
$$;
revoke execute on function painel.salvar_ficha_entrevista(uuid, jsonb, jsonb) from public, anon;
grant execute on function painel.salvar_ficha_entrevista(uuid, jsonb, jsonb) to authenticated;

------------------------------------------------------------------------------
-- Remove a PRÓPRIA ficha (exige motivo; o conteúdo apagado fica em interno.auditoria). A remoção por id de ficha de
-- outro avaliador deixa de existir.
------------------------------------------------------------------------------
drop function painel.remover_ficha_entrevista(uuid, text);
create function painel.remover_minha_ficha(p_inscricao_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 5 then
    raise exception 'Informe o motivo da remoção (mín. 5 caracteres).' using errcode = 'P0001', hint = 'motivo_obrigatorio';
  end if;
  select f.id into v_id from interno.fichas_entrevista f where f.inscricao_id = p_inscricao_id and f.avaliador_id = auth.uid();
  if v_id is null then
    raise exception 'Você não tem ficha para este candidato.' using errcode = 'P0001', hint = 'sem_ficha';
  end if;
  insert into interno.auditoria (ator_id, ator_role, acao, entidade, entidade_id, dados_depois)
  values (auth.uid(), 'authenticated', 'MOTIVO_REMOCAO_FICHA', 'interno.fichas_entrevista', v_id::text,
          jsonb_build_object('motivo', btrim(p_motivo)));
  delete from interno.fichas_entrevista where id = v_id;
end;
$$;
revoke execute on function painel.remover_minha_ficha(uuid, text) from public, anon;
grant execute on function painel.remover_minha_ficha(uuid, text) to authenticated;
revoke execute on function painel.minhas_entrevistas() from public, anon;
grant execute on function painel.minhas_entrevistas() to authenticated;

------------------------------------------------------------------------------
-- Classificação: ET e PF só com 3+ fichas (troca de texto; erro se o trecho não for encontrado).
------------------------------------------------------------------------------
do $$
declare d text; ancora text;
begin
  d := pg_get_functiondef('painel.classificacao_final(publico.grupo_vaga, publico.nivel_vaga)'::regprocedure);
  ancora := '(select round(avg(f.total), 2) from interno.fichas_entrevista f where f.inscricao_id = i.id) as et';
  if position(ancora in d) = 0 then raise exception 'classificacao_final: cálculo da ET não encontrado'; end if;
  d := replace(d, ancora, 'interno.media_entrevista(i.id) as et');
  execute d;

  -- Usuários do painel: não mostra mais o total de cada ficha (vazava a nota individual) e liga pela autoria
  d := pg_get_functiondef('painel.listar_usuarios_painel()'::regprocedure);
  ancora := '''avaliador_informado'', f.avaliador_nome, ''total'', f.total, ''lancada_em'', f.created_at';
  if position(ancora in d) = 0 then raise exception 'listar_usuarios_painel: trecho das fichas não encontrado'; end if;
  d := replace(d, ancora, '''avaliador_informado'', f.avaliador_nome, ''lancada_em'', f.created_at');
  if position('f.lancado_por = u.user_id' in d) = 0 then raise exception 'listar_usuarios_painel: filtro por autor não encontrado'; end if;
  d := replace(d, 'f.lancado_por = u.user_id', 'f.avaliador_id = u.user_id');
  execute d;
end;
$$;
