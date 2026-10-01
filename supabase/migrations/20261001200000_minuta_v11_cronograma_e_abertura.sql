-- Minuta v11 do edital (recebida 01/10/2026), em relação à v9 (29/09/2026, versão até então vigente).
-- Diff de texto completo (825 parágrafos nas duas): só 6 mudanças de conteúdo, todas aplicadas aqui.
--
--   1) Item 4.3: horário exato da abertura e do encerramento das inscrições, antes ambíguo (N1 das decisões
--      pendentes). "das 8h do dia 05/10/2026 às 23h59 do dia 20/10/2026 (horário de Brasília)". O encerramento
--      já estava correto (23h59); só a abertura muda de 00h00 para 08h00.
--   2) Itens 2.1 e 11.1: cadastro de reserva passa de "3 por Grupo" (30 no total) para "2 (dois) candidatos por
--      vaga" (Júnior 6, Pleno 8, Sênior 6; total 20). Resolve a divergência que a seção 11, item 6 deste arquivo
--      registrava entre o quadro do item 2.1 e o item 11.1 da minuta antiga. Não há tabela de cadastro de reserva
--      no banco ainda (a funcionalidade não foi construída); fica registrado aqui para quando for.
--   3) Item 4.13 (novo): candidato deferido em recurso contra indeferimento de inscrição tem habilitação e AC
--      concluídas "nas mesmas condições dos demais candidatos" antes do resultado preliminar — é a base do
--      ajuste de cronograma abaixo (item 12).
--   4) Anexo IV, item 3 (Período de inscrições): o texto da data passa a citar o horário (8h a 23h59), igual ao
--      item 4.3; as datas em si não mudam (05/10 a 20/10).
--   5) Anexo IV, item 12 (Habilitação + AC): "29/10 a 05/11" -> "29/10 a 06/11 (05 e 06/11 reservados à análise
--      dos candidatos deferidos em recurso)".
--   6) Anexo IV, item 13 (Decisão dos recursos contra indeferimento de inscrição): "até 05/11" -> "até 04/11"
--      (precisa sair ANTES dos dois dias reservados do item 12).
--   7) Anexo IV, item 24 (Homologação do resultado final): "até 11/12" (mesmo dia do resultado final, item 23)
--      -> "até 16/12" (5 dias depois).
--
-- O item 1.9 aparece no diff bruto só por uma quebra de parágrafo do Word (texto idêntico); não é mudança de
-- conteúdo. Nada mais mudou: taxa, Pix, isenção, critérios da AC, entrevista, desempate, requisitos por
-- Grupo/Nível, vagas imediatas e o Anexo III continuam iguais à v9.
--
-- As alterações do cronograma são feitas pela MESMA função que o painel usa para retificação (painel.
-- salvar_cronograma_item), com justificativa e auditoria, em nome de quem autorizou a mudança (não é escrita
-- direta na tabela). Reversão: supabase/rollback/20261001200000_minuta_v11_cronograma_e_abertura.down.sql

-- 1) horário exato de abertura (item 4.3 da v11)
update interno.configuracao
   set valor = to_jsonb('2026-10-05T08:00:00-03:00'::text),
       descricao = 'Abertura das inscrições (edital, minuta v11, item 4.3: 05/10/2026, a partir das 8h, horário de Brasília).'
 where chave = 'inscricoes_abertura';

-- 4), 5), 6) Anexo IV: aplicados via painel.salvar_cronograma_item, autenticado como José Gabriel Pereira da
-- Silva (usuário do painel que autorizou a atualização), com uma sessão de serviço criada só para esta migração.
do $$
declare
  v_uid uuid;
  v_sid uuid := gen_random_uuid();
  v_justificativa constant text := 'Minuta v11 do edital (recebida 01/10/2026): item 4.13 (novo) reserva 05 e 06/11 para a análise dos candidatos deferidos em recurso.';
begin
  select u.user_id into v_uid from interno.usuarios_internos u where u.email = 'josegabrielpo422@gmail.com' and u.ativo;
  if v_uid is null then
    raise exception 'Usuário do painel josegabrielpo422@gmail.com não encontrado; migração não aplicada.';
  end if;
  insert into interno.sessoes_painel (session_id, user_id) values (v_sid, v_uid);
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated', 'email', 'josegabrielpo422@gmail.com', 'session_id', v_sid)::text, true);
  execute 'set local role authenticated';

  perform painel.salvar_cronograma_item(3, 'Período de inscrições',
    '2026-10-05'::date, '2026-10-20'::date,
    '05/10/2026 (a partir das 8h) a 20/10/2026 (até as 23h59, horário de Brasília)',
    'Minuta v11 do edital (recebida 01/10/2026), item 4.3: horário exato de abertura e encerramento.');
  perform painel.salvar_cronograma_item(12, 'Habilitação documental e análise curricular (simultâneas)',
    '2026-10-29'::date, '2026-11-06'::date,
    '05 e 06/11 reservados à análise dos candidatos deferidos em recurso', v_justificativa);
  perform painel.salvar_cronograma_item(13, 'Decisão dos recursos contra indeferimento de inscrição',
    null, '2026-11-04'::date, null, v_justificativa);
  perform painel.salvar_cronograma_item(24, 'Homologação do resultado final',
    null, '2026-12-16'::date, null, 'Minuta v11 do edital (recebida 01/10/2026): homologação passa a sair 5 dias após o resultado final, não mais no mesmo dia.');

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end;
$$;
