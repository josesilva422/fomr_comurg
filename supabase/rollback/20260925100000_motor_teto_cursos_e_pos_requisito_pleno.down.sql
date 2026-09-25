-- Volta o motor ao estado anterior (v4-2026-09-24): teto de cursos aplicado item a item e pós do Pleno sempre pontuando.

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
  -- Especialização/MBA: 2,0 pts por título, SEM limite de quantidade (edital atualizado 22/09/2026) — só o
  -- teto global do critério (10,0, aplicado no clamp ao final do laço) limita a soma. Mestrado e doutorado
  -- continuam com máximo de 1 título cada (inalterado).
  ----------------------------------------------------------------------------
  for r in select * from publico.titulos_declarados where inscricao_id = p_inscricao_id order by data_conclusao, created_at
  loop
    pts := 0; motivo := null;
    if r.id = excluir_titulo_id then
      motivo := 'Usado para cumprir o requisito obrigatório de pós-graduação do nível Sênior; não pontua (Anexo I, item 1).';
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
      'cursos', jsonb_build_object('itens', det_cursos, 'total', pontos_cursos, 'teto', 15),
      'experiencia', jsonb_build_object('minimo_meses', minimo_meses, 'meses_comprovados', meses, 'excedente_meses', excedente, 'pontos', pontos_experiencia, 'teto', 35),
      'avisos_metodologicos', jsonb_build_array(
        'Faixas de experiência tratadas como intervalos (0,12], (12,36], (36,60], (60,∞) meses — convenção assumida; ver decisão pendente nº 1.',
        'Equivalência de pós-graduação no nível Pleno (título OU 5 anos OU certificação ativa no Grupo B) — convenção assumida; ver decisão pendente nº 4.',
        'Correlação de títulos/cursos com as atribuições do Grupo não é verificada automaticamente; exige confirmação da Comissão.',
        'Autenticidade de diplomas/certificados (e-MEC, Diplomas Digitais do MEC, portais de certificadoras) não é verificada aqui; é etapa manual da Comissão.',
        'Título ou curso sem documento comprobatório anexado não pontua (decisão do responsável, 22/09/2026).',
        'Especialização/MBA sem limite de quantidade, respeitando o teto global de 10,0 pts (edital atualizado em 22/09/2026, Anexo I item 1).'
      )
    ),
    'v4-2026-09-24'
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
select interno.recalcular_todas();
