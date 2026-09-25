-- Pós-graduação exigida no Sênior e no Pleno só vale com o certificado anexado (pedido do responsável, 25/09/2026 —
-- mesma regra aplicada à experiência na migração 20260925110000). O edital exige, para inscrever-se, atender aos
-- requisitos (3.1, alínea d; 3.2 a 3.4) e comprova a pós por certificado (5.2.1); documento ausente não é considerado (5.5.1).
--
--   Sênior (3.2.3, 3.3.3, 3.4.3): pós lato sensu obrigatória → precisa de especialização COM certificado anexado.
--   Pleno (3.2.2, 3.3.2, 3.4.2): especialização com certificado OU 5 anos de experiência comprovada (vínculos com
--     comprovante, migração 20260925110000) OU, no Grupo B, certificação PMP/PgMP/PRINCE2/IPMA ativa com certificado anexado.
--
-- O que muda:
--   * interno.pos_requisito_titulo_id(uuid): especialização que cumpre o requisito (com certificado; prefere ≥ 360h);
--   * interno.pleno_tem_equivalencia(uuid): equivalência do Pleno, só com experiência/certificação comprovadas;
--   * publico.verificar_inscricao(): pendência BLOQUEANTE "pos_sem_comprovante" (etapa 3) no Sênior e no Pleno;
--   * interno.calcular_avaliacao(): usa as duas funções; mensagens citam o certificado; versão v7-2026-09-25.
-- A validade do certificado (IES credenciada, 360h, área) continua sendo conferida pela Comissão.
-- Reversão: supabase/rollback/20260925120000_comprovante_pos_requisito.down.sql

create or replace function interno.pos_requisito_titulo_id(p_inscricao_id uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select t.id from publico.titulos_declarados t
  where t.inscricao_id = p_inscricao_id and t.tipo = 'especializacao'
    and exists (select 1 from publico.documentos d where d.titulo_id = t.id and d.ativo)
  order by (t.carga_horaria >= 360) desc, t.created_at
  limit 1
$$;

create or replace function interno.pleno_tem_equivalencia(p_inscricao_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select interno.meses_experiencia_uniao(p_inscricao_id) >= 60
      or exists (
        select 1 from publico.inscricoes i
        join publico.cursos_declarados k on k.inscricao_id = i.id
        where i.id = p_inscricao_id and i.grupo = 'B' and k.tipo = 'certificacao'
          and (k.denominacao ilike '%PMP%' or k.denominacao ilike '%PgMP%' or k.denominacao ilike '%PRINCE2%' or k.denominacao ilike '%IPMA%')
          and k.numero_credencial is not null and k.codigo_verificacao is not null
          and exists (select 1 from publico.documentos d where d.curso_id = k.id and d.ativo))
$$;
revoke execute on function interno.pos_requisito_titulo_id(uuid), interno.pleno_tem_equivalencia(uuid) from public, anon, authenticated;

------------------------------------------------------------------------------
-- Motor: requisito de pós pelas duas funções (troca de texto; erro se o trecho não for encontrado).
------------------------------------------------------------------------------
do $$
declare d text; ini int; fim int; ancora_fim text;
begin
  d := pg_get_functiondef('interno.calcular_avaliacao(uuid)'::regprocedure);

  ini := position('    tem_equivalencia := req_modo = ''equiv'' and (' in d);
  ancora_fim := '        limit 1;
    end if;
';
  fim := ini - 1 + position(ancora_fim in substr(d, ini));
  if ini = 0 or fim < ini then raise exception 'calcular_avaliacao: bloco do requisito de pós não encontrado'; end if;
  d := left(d, ini - 1)
    || '    -- 5.2.1 e 5.5.1: só vale especialização com certificado anexado; equivalência só com experiência/certificação
    -- comprovadas (interno.pleno_tem_equivalencia, interno.pos_requisito_titulo_id — migração 20260925120000)
    tem_equivalencia := req_modo = ''equiv'' and interno.pleno_tem_equivalencia(p_inscricao_id);
    if not tem_equivalencia then
      excluir_titulo_id := interno.pos_requisito_titulo_id(p_inscricao_id);
    end if;
'
    || substr(d, fim + length(ancora_fim));

  if position('''Pós-graduação lato sensu obrigatória para o nível Sênior não foi declarada.''' in d) = 0 then
    raise exception 'calcular_avaliacao: mensagem do Sênior não encontrada';
  end if;
  d := replace(d, '''Pós-graduação lato sensu obrigatória para o nível Sênior não foi declarada.''',
    '''Pós-graduação lato sensu obrigatória para o nível Sênior não foi comprovada: nenhuma especialização com certificado anexado (itens 3.2.3/3.3.3/3.4.3 e 5.2.1).''');
  if position('''Pós-graduação ou equivalência exigida para o nível Pleno não foi atendida.''' in d) = 0 then
    raise exception 'calcular_avaliacao: mensagem do Pleno não encontrada';
  end if;
  d := replace(d, '''Pós-graduação ou equivalência exigida para o nível Pleno não foi atendida.''',
    '''Pós-graduação ou equivalência exigida para o nível Pleno não foi comprovada: nenhuma especialização com certificado anexado, nem 5 anos de experiência comprovada, nem (Grupo B) certificação ativa com certificado anexado (itens 3.2.2/3.3.2/3.4.2 e 5.2.1).''');

  ancora_fim := 'A validade do documento e a área da experiência são conferidas pela Comissão.''';
  if position(ancora_fim in d) = 0 then raise exception 'calcular_avaliacao: aviso de experiência não encontrado'; end if;
  d := replace(d, ancora_fim, ancora_fim || ',
        ''Pós-graduação exigida (Sênior; Pleno sem equivalência): só vale especialização com certificado anexado (5.2.1). Equivalência do Pleno: 5 anos de experiência comprovada ou, no Grupo B, certificação ativa com certificado anexado. IES credenciada, 360h e área são conferidas pela Comissão.''');

  if position('''v6-2026-09-25''' in d) = 0 then raise exception 'calcular_avaliacao: versão v6 não encontrada'; end if;
  d := replace(d, '''v6-2026-09-25''', '''v7-2026-09-25''');
  execute d;
end;
$$;

------------------------------------------------------------------------------
-- Portal: pendência bloqueante da pós exigida (etapa 3 — formação).
------------------------------------------------------------------------------
do $$
declare d text; ancora text;
begin
  d := pg_get_functiondef('publico.verificar_inscricao()'::regprocedure);
  -- âncora em código (não em comentário: em produção a função foi gravada sem comentários)
  ancora := '  for r in
    select t.denominacao from publico.titulos_declarados t';
  if position(ancora in d) = 0 then raise exception 'verificar_inscricao: laço dos títulos sem documento não encontrado'; end if;
  d := replace(d, ancora,
'  -- pós exigida (3.1 d; 3.2 a 3.4; 5.2.1): Sênior sempre; Pleno quando não há equivalência comprovada
  if i.nivel = ''senior'' and interno.pos_requisito_titulo_id(i.id) is null then
    return query select ''pos_sem_comprovante''::text,
      ''Nível Sênior: a pós-graduação lato sensu é obrigatória. Cadastre a especialização e anexe o certificado.''::text, 3, true;
  elsif i.nivel = ''pleno'' and interno.pos_requisito_titulo_id(i.id) is null and not interno.pleno_tem_equivalencia(i.id) then
    return query select ''pos_sem_comprovante''::text,
      (''Nível Pleno: cadastre a pós-graduação lato sensu e anexe o certificado. Sem ela, o requisito só é cumprido com 5 anos de experiência comprovada''
       || case when i.grupo = ''B'' then '' ou com certificação PMP, PgMP, PRINCE2 ou IPMA ativa, com o certificado anexado.'' else ''.'' end)::text, 3, true;
  end if;

' || ancora);
  execute d;
end;
$$;

select interno.recalcular_todas();
