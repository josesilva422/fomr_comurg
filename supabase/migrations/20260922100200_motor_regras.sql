-- Fase 2 · Motor de regras: habilitação + pontuação da análise curricular (edital, item 6.4 e Anexo I).
-- Python puro está fora de alcance para hoje; a mesma responsabilidade (funções puras, sem IA, citando o
-- item do edital) foi implementada em SQL, no schema `interno`, seguindo a convenção já usada no projeto
-- (ex.: publico.verificar_inscricao). Nenhum resultado aqui é definitivo: fica em avaliacoes_curriculares
-- com status 'rascunho' até um humano da Comissão revisar e aprovar (CLAUDE.md, princípio 2).
--
-- ASSUNÇÕES tomadas por decisão ainda pendente (ver docs/decisoes-pendentes.md, itens 1 e 4) — citadas
-- também no código abaixo:
--   (a) faixas de experiência excedente: intervalos (0,12], (12,36], (36,60], (60,∞) meses;
--   (b) equivalência da pós no nível Pleno: título OU 5 anos de experiência OU (Grupo B) certificação
--       PMP/PgMP/PRINCE2/IPMA ativa: qualquer um dos três libera a habilitação quanto a esse requisito,
--       e NÃO é descontado da pontuação (só a pós obrigatória do Sênior desconta 1 título, ver abaixo).
-- Reversão: supabase/rollback/20260922100200_motor_regras.down.sql

------------------------------------------------------------------------------
-- Experiência: união de meses (mesma regra do item 5.4.1/5.4.2, já usada no formulário em TypeScript).
-- Vínculo ativo conta até o mês de encerramento das inscrições.
------------------------------------------------------------------------------
create or replace function interno.meses_experiencia_uniao(p_inscricao_id uuid)
returns integer
language sql stable security definer set search_path = ''
as $$
  with encerramento_mes as (
    select (extract(year from d)::int * 12 + extract(month from d)::int - 1) as m
    from (select (interno.encerramento() at time zone 'America/Sao_Paulo')::date as d) x
  ),
  base as (
    select
      (extract(year from v.inicio)::int * 12 + extract(month from v.inicio)::int - 1) as ini,
      case when v.ativo then (select m from encerramento_mes)
           else (extract(year from v.fim)::int * 12 + extract(month from v.fim)::int - 1) end as fim
    from publico.vinculos_declarados v
    where v.inscricao_id = p_inscricao_id
  ),
  validos as (
    select ini, fim from base where fim >= ini
  ),
  com_anterior as (
    select ini, fim,
           max(fim) over (order by ini, fim rows between unbounded preceding and 1 preceding) as fim_max_ant
    from validos
  ),
  grupos as (
    select ini, fim,
           sum(case when fim_max_ant is null or ini > fim_max_ant + 1 then 1 else 0 end) over (order by ini, fim) as grp
    from com_anterior
  )
  select coalesce(sum(mx - mn + 1), 0)::int
  from (select grp, min(ini) as mn, max(fim) as mx from grupos group by grp) t
$$;

------------------------------------------------------------------------------
-- Cálculo completo: habilitação + pontuação, com detalhamento item a item.
------------------------------------------------------------------------------
create or replace function interno.calcular_avaliacao(p_inscricao_id uuid)
returns interno.avaliacoes_curriculares
language plpgsql security definer set search_path = ''
as $$
declare
  i publico.inscricoes;
  minimo_meses int;
  meses int;
  excedente int;
  motivos jsonb := '[]'::jsonb;
  habilitado boolean := true;
  pontos_formacao numeric(5,2) := 0;
  pontos_cursos numeric(5,2) := 0;
  pontos_experiencia numeric(5,2) := 0;
  det_formacao jsonb := '[]'::jsonb;
  det_cursos jsonb := '[]'::jsonb;
  req_modo text;
  excluir_titulo_id uuid;
  atende_pos boolean;
  r record;
  n_esp int := 0;
  n_mestrado int := 0;
  n_doutorado int := 0;
  pub_edital constant date := '2026-09-24';
  faixa_20_39 numeric := 0;
  faixa_40_79 numeric := 0;
  faixa_80 numeric := 0;
  resultado interno.avaliacoes_curriculares;
  pts numeric(5,2);
  motivo text;
  no_catalogo boolean;
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

  if req_modo = 'obrig' then
    select t.id into excluir_titulo_id from publico.titulos_declarados t
      where t.inscricao_id = p_inscricao_id and t.tipo = 'especializacao'
      order by t.created_at limit 1;
    if excluir_titulo_id is null then
      habilitado := false;
      motivos := motivos || jsonb_build_object('codigo', 'pos_obrigatoria_ausente',
        'mensagem', 'Pós-graduação lato sensu obrigatória para o nível Sênior não foi declarada.');
    end if;
  elsif req_modo = 'equiv' then
    atende_pos := exists (select 1 from publico.titulos_declarados t where t.inscricao_id = p_inscricao_id and t.tipo = 'especializacao')
      or meses >= 60
      or (i.grupo = 'B' and exists (
            select 1 from publico.cursos_declarados k
            where k.inscricao_id = p_inscricao_id and k.tipo = 'certificacao'
              and (k.denominacao ilike '%PMP%' or k.denominacao ilike '%PgMP%' or k.denominacao ilike '%PRINCE2%' or k.denominacao ilike '%IPMA%')
              and k.numero_credencial is not null and k.codigo_verificacao is not null
          ));
    if not atende_pos then
      habilitado := false;
      motivos := motivos || jsonb_build_object('codigo', 'pos_ou_equivalencia_ausente',
        'mensagem', 'Pós-graduação ou equivalência exigida para o nível Pleno não foi atendida.');
    end if;
  end if;

  ----------------------------------------------------------------------------
  -- Anexo I, item 1 · Formação Acadêmica Adicional (máx. 10,0)
  ----------------------------------------------------------------------------
  for r in select * from publico.titulos_declarados where inscricao_id = p_inscricao_id order by data_conclusao, created_at
  loop
    pts := 0; motivo := null;
    if r.id = excluir_titulo_id then
      motivo := 'Usado para cumprir o requisito obrigatório de pós-graduação do nível Sênior; não pontua (Anexo I, item 1).';
    elsif r.data_conclusao > pub_edital then
      motivo := 'Concluído depois da publicação do edital (24/09/2026); não pontua.';
    elsif r.tipo = 'especializacao' then
      if r.carga_horaria < 360 then
        motivo := 'Carga horária inferior a 360h; não pontua.';
      elsif n_esp >= 3 then
        motivo := 'Limite de 3 títulos de especialização/MBA já atingido (até 6,0 pontos).';
      else
        n_esp := n_esp + 1; pts := 2.0;
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
  ----------------------------------------------------------------------------
  for r in select * from publico.cursos_declarados where inscricao_id = p_inscricao_id order by data_conclusao, created_at
  loop
    pts := 0; motivo := null;
    no_catalogo := i.grupo is not null and exists (
      select 1 from interno.cursos_pontuaveis cp where cp.grupo = i.grupo and lower(r.denominacao) like '%' || lower(cp.denominacao) || '%'
    );
    if r.data_conclusao > pub_edital then
      motivo := 'Concluído depois da publicação do edital (24/09/2026); não pontua.';
    elsif r.tipo = 'curso' then
      if r.carga_horaria < 20 then
        motivo := 'Carga horária inferior a 20h; não pontua.';
      elsif pontos_cursos >= 15 then
        motivo := 'Teto global de 15,0 pontos do critério já atingido.';
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
      if pontos_cursos >= 15 then motivo := 'Teto global de 15,0 pontos do critério já atingido.'; else pts := 5.0; end if;
    end if;
    if pts > 0 and pontos_cursos + pts > 15 then pts := 0; motivo := 'Teto global de 15,0 pontos do critério já atingido.'; end if;
    pontos_cursos := pontos_cursos + pts;
    det_cursos := det_cursos || jsonb_build_object(
      'id', r.id, 'tipo', r.tipo, 'denominacao', r.denominacao, 'carga_horaria', r.carga_horaria,
      'data_conclusao', r.data_conclusao, 'pontos', pts, 'motivo_rejeicao', motivo, 'no_catalogo_do_grupo', no_catalogo,
      'observacao', case when pts > 0 and not no_catalogo then 'Fora do catálogo exemplificativo (Anexo I, item 2.1); pontua se a Comissão confirmar correlação com o Grupo.' else null end
    );
  end loop;

  ----------------------------------------------------------------------------
  -- Anexo I, item 3 · Experiência Profissional Específica (máx. 35,0, por degrau)
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
      'cursos', jsonb_build_object('itens', det_cursos, 'total', pontos_cursos, 'teto', 15),
      'experiencia', jsonb_build_object('minimo_meses', minimo_meses, 'meses_comprovados', meses, 'excedente_meses', excedente, 'pontos', pontos_experiencia, 'teto', 35),
      'avisos_metodologicos', jsonb_build_array(
        'Faixas de experiência tratadas como intervalos (0,12], (12,36], (36,60], (60,∞) meses — convenção assumida; ver decisão pendente nº 1.',
        'Equivalência de pós-graduação no nível Pleno (título OU 5 anos OU certificação ativa no Grupo B) — convenção assumida; ver decisão pendente nº 4.',
        'Correlação de títulos/cursos com as atribuições do Grupo não é verificada automaticamente; exige confirmação da Comissão.',
        'Autenticidade de diplomas/certificados (e-MEC, Diplomas Digitais do MEC, portais de certificadoras) não é verificada aqui; é etapa manual da Comissão.'
      )
    ),
    'v1-2026-09-22'
  )
  on conflict (inscricao_id) do update set
    habilitado = excluded.habilitado, motivos = excluded.motivos,
    pontos_formacao = excluded.pontos_formacao, pontos_cursos = excluded.pontos_cursos,
    pontos_experiencia = excluded.pontos_experiencia, total = excluded.total,
    detalhamento = excluded.detalhamento, versao_motor = excluded.versao_motor, calculado_em = now()
  returning * into resultado;

  return resultado;
end;
$$;

revoke execute on function interno.meses_experiencia_uniao(uuid), interno.calcular_avaliacao(uuid) from public, anon, authenticated;
