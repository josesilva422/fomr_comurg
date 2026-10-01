-- Anexo I, item 2.1: a lista de cursos/certificações pontuáveis por Grupo é EXEMPLIFICATIVA — curso fora dela pode
-- pontuar "por deliberação motivada da Comissão". Hoje o motor já SINALIZA o item fora do catálogo
-- (`no_catalogo_do_grupo` no detalhamento), mas pontua automaticamente, sem registrar decisão nenhuma.
-- Esta migração cria o registro da deliberação e muda o motor para respeitá-la:
--   * sem deliberação ainda: comportamento igual a antes (pontua, com o aviso de "pendente de confirmação");
--   * deliberação 'aceito': pontua, com o aviso de "aceito por deliberação motivada";
--   * deliberação 'recusado': NÃO pontua (nem consome a faixa de carga horária), com o motivo registrado.
-- Decisão humana, motivada e registrada (itens 1.5 e 1.6); o motor nunca decide sozinho.
-- Reversão: supabase/rollback/20261001100000_deliberacao_cursos_fora_catalogo.down.sql

create table interno.deliberacoes_curso (
  id           uuid primary key default gen_random_uuid(),
  curso_id     uuid not null references publico.cursos_declarados (id),
  decisao      text not null check (decisao in ('aceito', 'recusado')),
  motivo       text not null check (char_length(btrim(motivo)) >= 10),
  decidido_por uuid not null,
  decidido_em  timestamptz not null default clock_timestamp()
);
create index deliberacoes_curso_curso_idx on interno.deliberacoes_curso (curso_id, decidido_em desc);
alter table interno.deliberacoes_curso enable row level security;
revoke all on interno.deliberacoes_curso from public, anon, authenticated;
create trigger deliberacoes_curso_auditoria after insert or update or delete on interno.deliberacoes_curso
  for each row execute function interno.registrar_auditoria();

------------------------------------------------------------------------------
-- Motor: respeita a deliberação mais recente de cada curso fora do catálogo
------------------------------------------------------------------------------
create or replace function interno.calcular_avaliacao(p_inscricao_id uuid)
returns interno.avaliacoes_curriculares
language plpgsql security definer set search_path = ''
as $function$
declare
  i publico.inscricoes;
  minimo_meses int;
  meses int;
  excedente int;
  motivos jsonb := '[]'::jsonb;
  habilitado boolean := true;
  pontos_formacao numeric(5,2) := 0;
  pontos_cursos numeric(5,2) := 0;
  soma_cursos numeric(6,2) := 0;
  pontos_experiencia numeric(5,2) := 0;
  det_formacao jsonb := '[]'::jsonb;
  det_cursos jsonb := '[]'::jsonb;
  req_modo text;
  excluir_titulo_id uuid;
  tem_equivalencia boolean;
  r record;
  n_mestrado int := 0;
  n_doutorado int := 0;
  pub_edital constant date := '2026-10-05';
  faixa_20_39 numeric := 0;
  faixa_40_79 numeric := 0;
  faixa_80 numeric := 0;
  resultado interno.avaliacoes_curriculares;
  pts numeric(5,2);
  motivo text;
  no_catalogo boolean;
  v_delib_decisao text;
  v_delib_motivo text;
begin
  select * into i from publico.inscricoes where id = p_inscricao_id;
  if not found then
    raise exception 'Inscrição não encontrada.' using errcode = 'P0001';
  end if;
  if i.grupo is null or i.nivel is null then
    raise exception 'Inscrição sem grupo/nível definido.' using errcode = 'P0001';
  end if;

  -- item 5.1.6: tecnólogo não é aceito em nenhum grupo ou nível
  if i.grau_graduacao = 'tecnologico' then
    habilitado := false;
    motivos := motivos || jsonb_build_object('codigo', 'grau_tecnologico',
      'mensagem', 'Formação em nível tecnólogo não é aceita em nenhum grupo ou nível (item 5.1.6).');
  end if;

  -- itens 3.2 a 3.4: o curso precisa constar na lista aceita para o grupo e o nível
  if not exists (
    select 1 from publico.cursos_aceitos a
    where a.grupo = i.grupo and a.nivel = i.nivel and a.curso = i.curso_graduacao
  ) then
    habilitado := false;
    motivos := motivos || jsonb_build_object('codigo', 'curso_fora_da_lista',
      'mensagem', 'O curso de graduação não consta na lista aceita para o grupo e o nível (itens 3.2 a 3.4).');
  end if;

  -- item 3.1 / tabela de requisitos por nível: experiência mínima
  minimo_meses := case i.nivel when 'junior' then 12 when 'pleno' then 48 when 'senior' then 96 end;
  meses := interno.meses_experiencia_uniao(p_inscricao_id);
  if meses < minimo_meses then
    habilitado := false;
    motivos := motivos || jsonb_build_object('codigo', 'experiencia_insuficiente',
      'mensagem', format('Experiência comprovada (%s meses) abaixo do mínimo exigido para o nível (%s meses).', meses, minimo_meses));
  end if;
  excedente := greatest(meses - minimo_meses, 0);

  -- pós-graduação: Júnior não exige; Sênior exige (obrigatória); Pleno exige com equivalência
  -- (itens 3.2.2/3.2.3, 3.3.2/3.3.3, 3.4.2/3.4.3 — ver REQUISITOS em requisitos.ts, mesma fonte)
  req_modo := case when i.nivel = 'junior' then 'nao' when i.nivel = 'senior' then 'obrig' else 'equiv' end;

  -- Título que cumpre o requisito de pós-graduação: não pontua (Anexo I, item 1: "Títulos utilizados como requisito
  -- mínimo de habilitação para o nível concorrido não serão pontuados"; item 6.4.3: vedada a dupla pontuação).
  -- Escolha determinística: primeiro o que atende o item 5.2.1 (≥ 360h) e tem documento anexado; depois o mais antigo.
  --   Sênior: pós obrigatória (3.2.3, 3.3.3, 3.4.3) — sempre desconta 1 título.
  --   Pleno: pós OU equivalência (3.2.2, 3.3.2, 3.4.2) — desconta 1 título só quando ele é o ÚNICO meio de cumprir o
  --   requisito (sem 5 anos de experiência e, no Grupo B, sem certificação ativa). Com equivalência também presente,
  --   o título pontua (decisão pendente nº 4).
  if req_modo = 'obrig' or req_modo = 'equiv' then
    -- 5.2.1 e 5.5.1: só vale especialização com certificado anexado; equivalência só com experiência/certificação
    -- comprovadas (interno.pleno_tem_equivalencia, interno.pos_requisito_titulo_id — migração 20260925120000)
    tem_equivalencia := req_modo = 'equiv' and interno.pleno_tem_equivalencia(p_inscricao_id);
    if not tem_equivalencia then
      excluir_titulo_id := interno.pos_requisito_titulo_id(p_inscricao_id);
    end if;
    if req_modo = 'obrig' and excluir_titulo_id is null then
      habilitado := false;
      motivos := motivos || jsonb_build_object('codigo', 'pos_obrigatoria_ausente',
        'mensagem', 'Pós-graduação lato sensu obrigatória para o nível Sênior não foi comprovada: nenhuma especialização com certificado anexado (itens 3.2.3/3.3.3/3.4.3 e 5.2.1).');
    elsif req_modo = 'equiv' and not tem_equivalencia and excluir_titulo_id is null then
      habilitado := false;
      motivos := motivos || jsonb_build_object('codigo', 'pos_ou_equivalencia_ausente',
        'mensagem', 'Pós-graduação ou equivalência exigida para o nível Pleno não foi comprovada: nenhuma especialização com certificado anexado, nem 5 anos de experiência comprovada, nem (Grupo B) certificação ativa com certificado anexado (itens 3.2.2/3.3.2/3.4.2 e 5.2.1).');
    end if;
  end if;

  ----------------------------------------------------------------------------
  -- Anexo I, item 1 · Formação Acadêmica Adicional (máx. 10,0)
  -- Especialização/MBA: 2,0 pts por título, SEM limite de quantidade (edital atualizado 22/09/2026) — só o
  -- teto global do critério (10,0, aplicado no clamp ao final do laço) limita a soma. Mestrado e doutorado
  -- continuam com máximo de 1 título cada (inalterado).
  ----------------------------------------------------------------------------
  for r in select * from publico.titulos_declarados where inscricao_id = p_inscricao_id order by data_conclusao, created_at
  loop
    pts := 0; motivo := null;
    if r.id = excluir_titulo_id then
      motivo := case when req_modo = 'obrig'
        then 'Usado para cumprir o requisito obrigatório de pós-graduação do nível Sênior; não pontua (Anexo I, item 1).'
        else 'Usado para cumprir o requisito de pós-graduação do nível Pleno (sem equivalência por 5 anos de experiência ou certificação); não pontua (Anexo I, item 1; item 6.4.3).' end;
    elsif not exists (select 1 from publico.documentos d where d.titulo_id = r.id and d.ativo) then
      motivo := 'Sem certificado ou diploma anexado; não pontua.';
    elsif r.data_conclusao > pub_edital then
      motivo := 'Concluído depois da publicação do edital (05/10/2026); não pontua.';
    elsif r.tipo = 'especializacao' then
      if r.carga_horaria < 360 then
        motivo := 'Carga horária inferior a 360h; não pontua.';
      else
        pts := 2.0;
      end if;
    elsif r.tipo = 'mestrado' then
      if n_mestrado >= 1 then motivo := 'Limite de 1 título de mestrado já atingido.'; else n_mestrado := 1; pts := 3.0; end if;
    elsif r.tipo = 'doutorado' then
      if n_doutorado >= 1 then motivo := 'Limite de 1 título de doutorado já atingido.'; else n_doutorado := 1; pts := 4.0; end if;
    end if;
    pontos_formacao := pontos_formacao + pts;
    det_formacao := det_formacao || jsonb_build_object(
      'id', r.id, 'tipo', r.tipo, 'denominacao', r.denominacao, 'data_conclusao', r.data_conclusao,
      'pontos', pts, 'motivo_rejeicao', motivo,
      'observacao', case when pts > 0 then 'Correlação com as atribuições do Grupo exige confirmação da Comissão (Anexo I, item 1).' else null end
    );
  end loop;
  if pontos_formacao > 10 then pontos_formacao := 10; end if;

  ----------------------------------------------------------------------------
  -- Anexo I, item 2 · Cursos e Certificações Específicas (máx. 15,0; teto global rígido)
  -- Cada item pontua dentro do limite da sua faixa; o teto de 15,0 é aplicado sobre a SOMA, ao final do laço.
  -- Item 2.1: a lista por Grupo é exemplificativa. Fora da lista, só pontua enquanto não houver deliberação da
  -- Comissão recusando o item (interno.deliberacoes_curso, a mais recente vale); com recusa, pts = 0 e nem entra
  -- na faixa de carga horária.
  ----------------------------------------------------------------------------
  for r in select * from publico.cursos_declarados where inscricao_id = p_inscricao_id order by data_conclusao, created_at
  loop
    pts := 0; motivo := null;
    no_catalogo := i.grupo is not null and exists (
      select 1 from interno.cursos_pontuaveis cp where cp.grupo = i.grupo and lower(r.denominacao) like '%' || lower(cp.denominacao) || '%'
    );
    select x.decisao, x.motivo into v_delib_decisao, v_delib_motivo
      from interno.deliberacoes_curso x where x.curso_id = r.id order by x.decidido_em desc limit 1;
    if not exists (select 1 from publico.documentos d where d.curso_id = r.id and d.ativo) then
      motivo := 'Sem certificado anexado; não pontua.';
    elsif r.data_conclusao > pub_edital then
      motivo := 'Concluído depois da publicação do edital (05/10/2026); não pontua.';
    elsif not no_catalogo and v_delib_decisao = 'recusado' then
      motivo := 'Fora do catálogo exemplificativo (Anexo I, item 2.1); a Comissão deliberou não computar: ' || coalesce(nullif(btrim(v_delib_motivo), ''), 'motivo não informado') || '.';
    elsif r.tipo = 'curso' then
      if r.carga_horaria < 20 then
        motivo := 'Carga horária inferior a 20h; não pontua.';
      elsif r.carga_horaria between 20 and 39 then
        if faixa_20_39 >= 5 then motivo := 'Limite da faixa de 20 a 39 horas já atingido (até 5,0 pontos).';
        else faixa_20_39 := faixa_20_39 + 1; pts := 1.0; end if;
      elsif r.carga_horaria between 40 and 79 then
        if faixa_40_79 >= 6 then motivo := 'Limite da faixa de 40 a 79 horas já atingido (até 6,0 pontos).';
        else faixa_40_79 := faixa_40_79 + 2; pts := 2.0; end if;
      else -- 80h ou mais
        if faixa_80 >= 9 then motivo := 'Limite da faixa de 80 horas ou mais já atingido (até 9,0 pontos).';
        else faixa_80 := faixa_80 + 3; pts := 3.0; end if;
      end if;
    elsif r.tipo = 'certificacao' then
      pts := 5.0;
    end if;
    soma_cursos := soma_cursos + pts;
    det_cursos := det_cursos || jsonb_build_object(
      'id', r.id, 'tipo', r.tipo, 'denominacao', r.denominacao, 'carga_horaria', r.carga_horaria,
      'data_conclusao', r.data_conclusao, 'pontos', pts, 'motivo_rejeicao', motivo, 'no_catalogo_do_grupo', no_catalogo,
      'deliberacao_decisao', case when not no_catalogo then v_delib_decisao else null end,
      'observacao', case
        when pts > 0 and not no_catalogo and v_delib_decisao = 'aceito' then 'Fora do catálogo exemplificativo; aceito por deliberação motivada da Comissão (Anexo I, item 2.1).'
        when pts > 0 and not no_catalogo then 'Fora do catálogo exemplificativo (Anexo I, item 2.1); pontua até a Comissão deliberar (ver painel > Cursos fora do catálogo).'
        else null
      end
    );
  end loop;
  pontos_cursos := least(soma_cursos, 15);

  ----------------------------------------------------------------------------
  -- Anexo I, item 3 · Experiência Profissional Específica (máx. 35,0, por degrau) — inalterado no edital novo
  ----------------------------------------------------------------------------
  if excedente = 0 then pontos_experiencia := 0;
  elsif excedente <= 12 then pontos_experiencia := 5.0;
  elsif excedente <= 36 then pontos_experiencia := 15.0;
  elsif excedente <= 60 then pontos_experiencia := 25.0;
  else pontos_experiencia := 35.0;
  end if;

  ----------------------------------------------------------------------------
  -- Grava o resultado (rascunho — aguarda revisão humana da Comissão)
  ----------------------------------------------------------------------------
  insert into interno.avaliacoes_curriculares
    (inscricao_id, habilitado, motivos, pontos_formacao, pontos_cursos, pontos_experiencia, total, detalhamento, versao_motor)
  values (
    p_inscricao_id, habilitado, motivos, pontos_formacao, pontos_cursos, pontos_experiencia,
    pontos_formacao + pontos_cursos + pontos_experiencia,
    jsonb_build_object(
      'formacao', jsonb_build_object('itens', det_formacao, 'total', pontos_formacao, 'teto', 10),
      'cursos', jsonb_build_object('itens', det_cursos, 'total', pontos_cursos, 'soma_itens', soma_cursos, 'teto', 15),
      'experiencia', jsonb_build_object('vinculos_sem_comprovante', (select count(*) from publico.vinculos_declarados v where v.inscricao_id = p_inscricao_id and not interno.vinculo_comprovado(v.id)), 'minimo_meses', minimo_meses, 'meses_comprovados', meses, 'excedente_meses', excedente, 'pontos', pontos_experiencia, 'teto', 35),
      'avisos_metodologicos', jsonb_build_array(
        'Faixas de experiência conforme o edital (Anexo I, item 3, e item 6.4.2): excedente em meses completos — até 12 meses = 5,0; mais de 12 até 36 = 15,0; mais de 36 até 60 = 25,0; acima de 60 = 35,0; excedente menor que 1 mês não pontua.',
        'Pós-graduação no nível Pleno: título OU 5 anos de experiência OU (Grupo B) certificação PMP/PgMP/PRINCE2/IPMA ativa. Título que é o único meio de cumprir o requisito não pontua (Anexo I, item 1; item 6.4.3); com equivalência também presente, o título pontua — convenção assumida; ver decisão pendente nº 4.',
        'Correlação de títulos/cursos com as atribuições do Grupo não é verificada automaticamente; exige confirmação da Comissão.',
        'Autenticidade de diplomas/certificados (e-MEC, Diplomas Digitais do MEC, portais de certificadoras) não é verificada aqui; é etapa manual da Comissão.',
        'Título ou curso sem documento comprobatório anexado não pontua (decisão do responsável, 22/09/2026).',
        'Especialização/MBA sem limite de quantidade, respeitando o teto global de 10,0 pts (Anexo I, item 1).',
        'Cursos e certificações: cada item pontua dentro do limite da sua faixa e o teto de 15,0 é aplicado sobre a soma (Anexo I, item 2) — o resultado não depende da ordem dos itens.',
        'Curso/certificação fora do catálogo exemplificativo do Grupo (Anexo I, item 2.1): pontua até a Comissão deliberar; deliberação recusando o item zera a pontuação dele (painel > Cursos fora do catálogo).',
        'Experiência: só contam os vínculos com o comprovante do item 5.3 anexado (privado: CTPS, declaração ou contrato; público: certidão/declaração do órgão ou contrato administrativo; autônomo: contrato/RPA/nota fiscal + declaração do contratante). A validade do documento e a área da experiência são conferidas pela Comissão.',
        'Pós-graduação exigida (Sênior; Pleno sem equivalência): só vale especialização com certificado anexado (5.2.1). Equivalência do Pleno: 5 anos de experiência comprovada ou, no Grupo B, certificação ativa com certificado anexado. IES credenciada, 360h e área são conferidas pela Comissão.'
      )
    ),
    'v9-2026-10-01'
  )
  on conflict (inscricao_id) do update set
    habilitado = excluded.habilitado, motivos = excluded.motivos,
    pontos_formacao = excluded.pontos_formacao, pontos_cursos = excluded.pontos_cursos,
    pontos_experiencia = excluded.pontos_experiencia, total = excluded.total,
    detalhamento = excluded.detalhamento, versao_motor = excluded.versao_motor, calculado_em = now()
  returning * into resultado;

  return resultado;
end;
$function$;

------------------------------------------------------------------------------
-- Painel: lista dos itens fora do catálogo que pontuam (até deliberação) e a função de decidir
------------------------------------------------------------------------------
create or replace function painel.listar_cursos_fora_catalogo()
returns table (
  curso_id uuid, inscricao_id uuid, nome text, cpf text, grupo publico.grupo_vaga, nivel publico.nivel_vaga,
  tipo publico.tipo_curso, denominacao text, carga_horaria integer, data_conclusao date, pontos numeric,
  decisao text, motivo text, decidido_por_nome text, decidido_em timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  return query
    with inscricoes_com_curso as (
      select distinct cd.inscricao_id from publico.cursos_declarados cd
    ),
    avals as (
      select ic.inscricao_id, (interno.calcular_avaliacao(ic.inscricao_id)).detalhamento as det
      from inscricoes_com_curso ic
    ),
    itens as (
      select a.inscricao_id, jsonb_array_elements(a.det #> '{cursos,itens}') as item from avals a
    )
    select
      (it.item ->> 'id')::uuid, it.inscricao_id, c.nome, c.cpf, i.grupo, i.nivel,
      (it.item ->> 'tipo')::publico.tipo_curso, it.item ->> 'denominacao',
      nullif(it.item ->> 'carga_horaria', '')::integer, (it.item ->> 'data_conclusao')::date,
      (it.item ->> 'pontos')::numeric,
      dd.decisao, dd.motivo, coalesce(u.nome, '—'), dd.decidido_em
    from itens it
    join publico.inscricoes i on i.id = it.inscricao_id
    join publico.candidatos c on c.id = i.candidato_id
    left join lateral (
      select x.decisao, x.motivo, x.decidido_em, x.decidido_por from interno.deliberacoes_curso x
      where x.curso_id = (it.item ->> 'id')::uuid order by x.decidido_em desc limit 1
    ) dd on true
    left join interno.usuarios_internos u on u.user_id = dd.decidido_por
    where (it.item ->> 'no_catalogo_do_grupo')::boolean = false
      -- pendente de decisão (ainda pontua) OU já recusado (pts = 0, mas continua visível para eventual correção)
      and ((it.item ->> 'pontos')::numeric > 0 or it.item ->> 'deliberacao_decisao' = 'recusado')
    order by (dd.decisao is null) desc, c.nome;
end;
$$;

create or replace function painel.decidir_curso_catalogo(p_curso_id uuid, p_decisao text, p_motivo text)
returns interno.deliberacoes_curso
language plpgsql security definer set search_path = ''
as $$
declare
  v_insc uuid;
  r interno.deliberacoes_curso;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if p_decisao not in ('aceito', 'recusado') then
    raise exception 'Decisão inválida.' using errcode = 'P0001', hint = 'decisao_invalida';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'Informe o motivo da decisão (mínimo de 10 caracteres).' using errcode = 'P0001', hint = 'motivo_obrigatorio';
  end if;
  select cd.inscricao_id into v_insc from publico.cursos_declarados cd where cd.id = p_curso_id;
  if v_insc is null then
    raise exception 'Curso declarado não encontrado.' using errcode = 'P0001', hint = 'curso_nao_encontrado';
  end if;
  insert into interno.deliberacoes_curso (curso_id, decisao, motivo, decidido_por)
  values (p_curso_id, p_decisao, btrim(p_motivo), auth.uid())
  returning * into r;
  perform interno.calcular_avaliacao(v_insc);
  return r;
end;
$$;

revoke execute on function painel.listar_cursos_fora_catalogo(), painel.decidir_curso_catalogo(uuid, text, text) from public, anon;
grant execute on function painel.listar_cursos_fora_catalogo(), painel.decidir_curso_catalogo(uuid, text, text) to authenticated;
