-- Busca de inscrição por nome ou CPF, para a Comissão escolher a quem registrar um recurso (tela
-- /painel/recursos). Precisa cobrir TODOS os status, inclusive 'indeferida' (um recurso contra o
-- indeferimento da inscrição, item 9.1.b, é exatamente contra uma inscrição indeferida) — por isso não
-- reaproveita painel.listar_avaliacoes(), que só traz submetida/aguardando_isencao/homologada.
create or replace function painel.buscar_inscricao(p_busca text)
returns table(inscricao_id uuid, nome text, cpf text, grupo publico.grupo_vaga, nivel publico.nivel_vaga, status publico.status_inscricao)
language plpgsql
security definer
set search_path to ''
as $$
declare v_termo text := btrim(coalesce(p_busca, '')); v_cpf text := regexp_replace(coalesce(p_busca, ''), '\D', '', 'g');
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  if char_length(v_termo) < 3 then
    raise exception 'Digite ao menos 3 caracteres para buscar.' using errcode = 'P0001', hint = 'busca_curta';
  end if;
  return query
    select i.id, c.nome, c.cpf, i.grupo, i.nivel, i.status
    from publico.inscricoes i
    join publico.candidatos c on c.id = i.candidato_id
    where i.status <> 'rascunho'
      and (c.nome ilike '%' || v_termo || '%' or (v_cpf <> '' and c.cpf like '%' || v_cpf || '%'))
    order by c.nome
    limit 20;
end;
$$;
