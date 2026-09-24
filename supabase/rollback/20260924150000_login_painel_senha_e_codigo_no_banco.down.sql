create or replace function interno.eh_usuario_interno(p_user_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from interno.usuarios_internos u where u.user_id = p_user_id and u.ativo)
$$;
drop function if exists interno.definir_senha_painel(text, text);
drop function if exists painel.concluir_login();
drop function if exists painel.iniciar_login(text, text);
drop table if exists interno.sessoes_painel;
drop table if exists interno.desafios_login_painel;
delete from interno.configuracao where chave = 'painel_exige_login_seguro';
alter table interno.usuarios_internos
  drop column if exists senha_hash, drop column if exists cpf, drop column if exists tentativas_falhas, drop column if exists bloqueado_ate;
