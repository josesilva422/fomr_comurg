-- Restaura o estado da migração 20260922160000: painel.listar_avaliacoes() sem posicao/vagas/convocado,
-- remove painel.listar_cronograma() e as tabelas interno.vagas / interno.cronograma.

drop function if exists painel.listar_cronograma();

drop function if exists painel.listar_avaliacoes();
create function painel.listar_avaliacoes()
returns table (
  inscricao_id uuid, nome text, cpf text, email text, telefone text,
  grupo publico.grupo_vaga, nivel publico.nivel_vaga, status publico.status_inscricao,
  habilitado boolean, motivos jsonb,
  pontos_formacao numeric, pontos_cursos numeric, pontos_experiencia numeric, total numeric,
  submetida_em timestamptz, calculado_em timestamptz
)
language plpgsql security definer set search_path = ''
as $$
declare r record;
begin
  if not interno.eh_usuario_interno(auth.uid()) then
    raise exception 'Acesso restrito à Comissão.' using errcode = '42501';
  end if;
  for r in select x.id from publico.inscricoes x where x.status in ('submetida', 'aguardando_isencao', 'homologada')
  loop
    perform interno.calcular_avaliacao(r.id);
  end loop;
  return query
    select i.id, c.nome, c.cpf, c.email, c.telefone, i.grupo, i.nivel, i.status,
           a.habilitado, a.motivos, a.pontos_formacao, a.pontos_cursos, a.pontos_experiencia, a.total,
           i.submetida_em, a.calculado_em
    from publico.inscricoes i
    join publico.candidatos c on c.id = i.candidato_id
    join interno.avaliacoes_curriculares a on a.inscricao_id = i.id
    where i.status in ('submetida', 'aguardando_isencao', 'homologada')
    order by i.grupo, i.nivel, a.total desc nulls last;
end;
$$;

revoke execute on function painel.listar_avaliacoes() from public, anon;
grant execute on function painel.listar_avaliacoes() to authenticated;

drop table if exists interno.cronograma;
drop table if exists interno.vagas;
