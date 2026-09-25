-- Correções do motor de regras apontadas na conferência com o edital publicado (Nº 001/2026, 28/09/2026), em 25/09/2026:
--
-- (1) Cursos e certificações (Anexo I, item 2): o teto de 15,0 passa a ser aplicado sobre a SOMA dos itens, ao final
--     do laço (como já era na formação adicional). Antes, um item que ultrapassaria 15 recebia 0, e o resultado
--     dependia da ordem dos itens — ex.: 4 cursos ≥ 80h (9,0) + 1 curso de 40h (2,0) + 1 certificação (5,0) = 16,
--     que pelo edital vale 15,0, dava 11,0 quando a certificação era a mais recente.
-- (2) Pós-graduação usada como requisito no nível Pleno (Anexo I, item 1: "Títulos utilizados como requisito mínimo de
--     habilitação para o nível concorrido não serão pontuados"; item 6.4.3): quando o título é o ÚNICO meio de cumprir o
--     requisito (sem 5 anos de experiência e, no Grupo B, sem certificação PMP/PgMP/PRINCE2/IPMA ativa), ele deixa de
--     pontuar — igual ao Sênior. Com equivalência também presente, continua pontuando (decisão pendente nº 4).
--     O título escolhido como requisito (Pleno e Sênior) passa a ser, de preferência, um que atende o item 5.2.1
--     (≥ 360h) e tem documento anexado; antes era sempre o primeiro cadastrado.
-- (6) Avisos metodológicos: as faixas de experiência deixam de ser "convenção assumida" (o edital publicado as define:
--     Anexo I, item 3, e item 6.4.2) e passam a citar o edital.
--
-- Versão do motor: v5-2026-09-25. Corte de títulos/cursos continua em 28/09/2026 (publicação do edital).
-- Reversão: supabase/rollback/20260925100000_motor_teto_cursos_e_pos_requisito_pleno.down.sql

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
  pub_edital constant date := '2026-09-28';
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

  -- Título que cumpre o requisito de pós-graduação: não pontua (Anexo I, item 1: "Títulos utilizados como requisito
  -- mínimo de habilitação para o nível concorrido não serão pontuados"; item 6.4.3: vedada a dupla pontuação).
  -- Escolha determinística: primeiro o que atende o item 5.2.1 (≥ 360h) e tem documento anexado; depois o mais antigo.
  --   Sênior: pós obrigatória (3.2.3, 3.3.3, 3.4.3) — sempre desconta 1 título.
  --   Pleno: pós OU equivalência (3.2.2, 3.3.2, 3.4.2) — desconta 1 título só quando ele é o ÚNICO meio de cumprir o
  --   requisito (sem 5 anos de experiência e, no Grupo B, sem certificação ativa). Com equivalência também presente,
  --   o título pontua (decisão pendente nº 4).
  if req_modo = 'obrig' or req_modo = 'equiv' then
    tem_equivalencia := req_modo = 'equiv' and (
      meses >= 60
      or (i.grupo = 'B' and exists (
            select 1 from publico.cursos_declarados k
            where k.inscricao_id = p_inscricao_id and k.tipo = 'certificacao'
              and (k.denominacao ilike '%PMP%' or k.denominacao ilike '%PgMP%' or k.denominacao ilike '%PRINCE2%' or k.denominacao ilike '%IPMA%')
              and k.numero_credencial is not null and k.codigo_verificacao is not null
          )));
    if not tem_equivalencia then
      select t.id into excluir_titulo_id from publico.titulos_declarados t
        where t.inscricao_id = p_inscricao_id and t.tipo = 'especializacao'
        order by (t.carga_horaria >= 360) desc,
                 exists (select 1 from publico.documentos d where d.titulo_id = t.id and d.ativo) desc,
                 t.created_at
        limit 1;
    end if;
    if req_modo = 'obrig' and excluir_titulo_id is null then
      habilitado := false;
      motivos := motivos || jsonb_build_object('codigo', 'pos_obrigatoria_ausente',
        'mensagem', 'Pós-graduação lato sensu obrigatória para o nível Sênior não foi declarada.');
    elsif req_modo = 'equiv' and not tem_equivalencia and excluir_titulo_id is null then
      habilitado := false;
      motivos := motivos || jsonb_build_object('codigo', 'pos_ou_equivalencia_ausente',
        'mensagem', 'Pós-graduação ou equivalência exigida para o nível Pleno não foi atendida.');
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
      motivo := 'Concluído depois da publicação do edital (28/09/2026); não pontua.';
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
  -- Cada item pontua dentro do limite da sua faixa; o teto de 15,0 é aplicado sobre a SOMA, ao final do laço
  -- (mesma forma da formação adicional). Assim o resultado não depende da ordem dos itens: antes, um item que
  -- passaria de 15 recebia 0 (ex.: 13 + certificação 5 dava 13, em vez de 15).
  ----------------------------------------------------------------------------
  for r in select * from publico.cursos_declarados where inscricao_id = p_inscricao_id order by data_conclusao, created_at
  loop
    pts := 0; motivo := null;
    no_catalogo := i.grupo is not null and exists (
      select 1 from interno.cursos_pontuaveis cp where cp.grupo = i.grupo and lower(r.denominacao) like '%' || lower(cp.denominacao) || '%'
    );
    if not exists (select 1 from publico.documentos d where d.curso_id = r.id and d.ativo) then
      motivo := 'Sem certificado anexado; não pontua.';
    elsif r.data_conclusao > pub_edital then
      motivo := 'Concluído depois da publicação do edital (28/09/2026); não pontua.';
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
      'observacao', case when pts > 0 and not no_catalogo then 'Fora do catálogo exemplificativo (Anexo I, item 2.1); pontua se a Comissão confirmar correlação com o Grupo.' else null end
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
      'experiencia', jsonb_build_object('minimo_meses', minimo_meses, 'meses_comprovados', meses, 'excedente_meses', excedente, 'pontos', pontos_experiencia, 'teto', 35),
      'avisos_metodologicos', jsonb_build_array(
        'Faixas de experiência conforme o edital (Anexo I, item 3, e item 6.4.2): excedente em meses completos — até 12 meses = 5,0; mais de 12 até 36 = 15,0; mais de 36 até 60 = 25,0; acima de 60 = 35,0; excedente menor que 1 mês não pontua.',
        'Pós-graduação no nível Pleno: título OU 5 anos de experiência OU (Grupo B) certificação PMP/PgMP/PRINCE2/IPMA ativa. Título que é o único meio de cumprir o requisito não pontua (Anexo I, item 1; item 6.4.3); com equivalência também presente, o título pontua — convenção assumida; ver decisão pendente nº 4.',
        'Correlação de títulos/cursos com as atribuições do Grupo não é verificada automaticamente; exige confirmação da Comissão.',
        'Autenticidade de diplomas/certificados (e-MEC, Diplomas Digitais do MEC, portais de certificadoras) não é verificada aqui; é etapa manual da Comissão.',
        'Título ou curso sem documento comprobatório anexado não pontua (decisão do responsável, 22/09/2026).',
        'Especialização/MBA sem limite de quantidade, respeitando o teto global de 10,0 pts (Anexo I, item 1).',
        'Cursos e certificações: cada item pontua dentro do limite da sua faixa e o teto de 15,0 é aplicado sobre a soma (Anexo I, item 2) — o resultado não depende da ordem dos itens.'
      )
    ),
    'v5-2026-09-25'
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


-- Recalcula as avaliações já existentes com a nova versão (continuam como rascunho até a revisão da Comissão).
select interno.recalcular_todas();
