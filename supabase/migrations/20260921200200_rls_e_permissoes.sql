-- Fase 1 · RLS e permissões. Regra: cada candidato só enxerga e altera a PRÓPRIA inscrição, e só até o encerramento.
-- Reversão: supabase/rollback/20260921200200_rls_e_permissoes.down.sql

------------------------------------------------------------------------------
-- Funções auxiliares das políticas
------------------------------------------------------------------------------
-- Inscrição do usuário logado (qualquer status)
create or replace function publico.minha_inscricao_id() returns uuid
language sql stable security definer set search_path = ''
as $$
  select i.id
  from publico.inscricoes i
  join publico.candidatos c on c.id = i.candidato_id
  where c.user_id = (select auth.uid())
$$;

-- Inscrição do usuário logado, somente enquanto ainda pode ser editada pelo candidato
create or replace function publico.minha_inscricao_editavel_id() returns uuid
language sql stable security definer set search_path = ''
as $$
  select i.id
  from publico.inscricoes i
  join publico.candidatos c on c.id = i.candidato_id
  where c.user_id = (select auth.uid())
    and i.status in ('rascunho', 'submetida', 'aguardando_isencao')
$$;

revoke execute on function publico.minha_inscricao_id(), publico.minha_inscricao_editavel_id() from public;
grant execute on function publico.minha_inscricao_id(), publico.minha_inscricao_editavel_id() to authenticated;

------------------------------------------------------------------------------
-- Ponto de partida: ninguém tem nada; concedemos apenas o necessário
------------------------------------------------------------------------------
revoke all on all tables in schema publico from public, anon, authenticated;

alter table publico.candidatos          enable row level security;
alter table publico.inscricoes          enable row level security;
alter table publico.titulos_declarados  enable row level security;
alter table publico.cursos_declarados   enable row level security;
alter table publico.vinculos_declarados enable row level security;
alter table publico.documentos          enable row level security;
alter table publico.cursos_aceitos      enable row level security;

------------------------------------------------------------------------------
-- candidatos
------------------------------------------------------------------------------
grant select on publico.candidatos to authenticated;
grant insert (user_id, nome, cpf, telefone, data_nascimento, nacionalidade) on publico.candidatos to authenticated;
grant update (nome, cpf, telefone, data_nascimento, nacionalidade) on publico.candidatos to authenticated;

create policy candidatos_select_proprio on publico.candidatos
  for select to authenticated using (user_id = (select auth.uid()));
create policy candidatos_insert_proprio on publico.candidatos
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy candidatos_update_proprio on publico.candidatos
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

------------------------------------------------------------------------------
-- inscricoes: sem INSERT/DELETE pela API; status e datas só mudam por funções
------------------------------------------------------------------------------
grant select on publico.inscricoes to authenticated;
grant update (grupo, nivel, curso_graduacao, grau_graduacao, instituicao_graduacao, data_colacao,
              formato_diploma, codigo_diploma_digital, diploma_provisorio, diploma_exterior,
              cota_pcd, data_laudo, cota_racial, solicitou_isencao, justificativa_isencao)
  on publico.inscricoes to authenticated;

create policy inscricoes_select_propria on publico.inscricoes
  for select to authenticated using (id = (select publico.minha_inscricao_id()));
create policy inscricoes_update_propria on publico.inscricoes
  for update to authenticated
  using (id = (select publico.minha_inscricao_editavel_id()))
  with check (id = (select publico.minha_inscricao_editavel_id()));

------------------------------------------------------------------------------
-- titulos_declarados, cursos_declarados, vinculos_declarados
------------------------------------------------------------------------------
grant select, delete on publico.titulos_declarados, publico.cursos_declarados, publico.vinculos_declarados to authenticated;
grant insert (inscricao_id, tipo, denominacao, instituicao, carga_horaria, data_conclusao)
  on publico.titulos_declarados to authenticated;
grant update (tipo, denominacao, instituicao, carga_horaria, data_conclusao)
  on publico.titulos_declarados to authenticated;
grant insert (inscricao_id, tipo, denominacao, instituicao, carga_horaria, data_conclusao, numero_credencial, codigo_verificacao)
  on publico.cursos_declarados to authenticated;
grant update (tipo, denominacao, instituicao, carga_horaria, data_conclusao, numero_credencial, codigo_verificacao)
  on publico.cursos_declarados to authenticated;
grant insert (inscricao_id, tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao)
  on publico.vinculos_declarados to authenticated;
grant update (tipo, empregador_contratante, cargo, inicio, fim, ativo, descricao)
  on publico.vinculos_declarados to authenticated;

do $$
declare t text;
begin
  foreach t in array array['titulos_declarados', 'cursos_declarados', 'vinculos_declarados']
  loop
    execute format('create policy %I on publico.%I for select to authenticated using (inscricao_id = (select publico.minha_inscricao_id()))',
                   t || '_select', t);
    execute format('create policy %I on publico.%I for insert to authenticated with check (inscricao_id = (select publico.minha_inscricao_editavel_id()))',
                   t || '_insert', t);
    execute format('create policy %I on publico.%I for update to authenticated using (inscricao_id = (select publico.minha_inscricao_editavel_id())) with check (inscricao_id = (select publico.minha_inscricao_editavel_id()))',
                   t || '_update', t);
    execute format('create policy %I on publico.%I for delete to authenticated using (inscricao_id = (select publico.minha_inscricao_editavel_id()))',
                   t || '_delete', t);
  end loop;
end;
$$;

------------------------------------------------------------------------------
-- documentos: candidato lê os próprios, insere novos e "remove" (ativo=false). Nunca apaga nem sobrescreve.
------------------------------------------------------------------------------
grant select on publico.documentos to authenticated;
grant insert (inscricao_id, tipo, titulo_id, curso_id, vinculo_id, storage_path, nome_original, sha256, mime, tamanho_bytes)
  on publico.documentos to authenticated;
grant update (ativo) on publico.documentos to authenticated;

create policy documentos_select on publico.documentos
  for select to authenticated using (inscricao_id = (select publico.minha_inscricao_id()));

-- O vínculo/título/curso citado precisa ser da MESMA inscrição
create policy documentos_insert on publico.documentos
  for insert to authenticated
  with check (
    inscricao_id = (select publico.minha_inscricao_editavel_id())
    and (titulo_id is null or exists (select 1 from publico.titulos_declarados x where x.id = titulo_id and x.inscricao_id = documentos.inscricao_id))
    and (curso_id  is null or exists (select 1 from publico.cursos_declarados  x where x.id = curso_id  and x.inscricao_id = documentos.inscricao_id))
    and (vinculo_id is null or exists (select 1 from publico.vinculos_declarados x where x.id = vinculo_id and x.inscricao_id = documentos.inscricao_id))
  );

create policy documentos_update_remocao on publico.documentos
  for update to authenticated
  using (inscricao_id = (select publico.minha_inscricao_editavel_id()))
  with check (inscricao_id = (select publico.minha_inscricao_editavel_id()));

------------------------------------------------------------------------------
-- cursos_aceitos: leitura para quem está logado
------------------------------------------------------------------------------
grant select on publico.cursos_aceitos to authenticated;
create policy cursos_aceitos_leitura on publico.cursos_aceitos
  for select to authenticated using (true);
