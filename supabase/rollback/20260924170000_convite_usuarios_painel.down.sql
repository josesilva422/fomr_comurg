drop function if exists painel.listar_convites();
drop function if exists painel.aceitar_convite(text, text, text, text);
drop function if exists painel.conferir_convite(text, text);
drop function if exists painel.criar_convite(text);
drop function if exists painel.posso_convidar();
drop table if exists interno.convites_painel;
drop index if exists interno.usuarios_internos_cpf_unico;
alter table interno.usuarios_internos drop column if exists pode_convidar, drop column if exists convidado_por;
create or replace function interno.definir_senha_painel(p_email text, p_senha text) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if char_length(coalesce(p_senha, '')) < 8
     or p_senha !~ '[A-Z]' or p_senha !~ '[a-z]' or p_senha !~ '[0-9]' or p_senha !~ '[^A-Za-z0-9]' then
    raise exception 'A senha precisa ter no mínimo 8 caracteres, com letra maiúscula, minúscula, número e caractere especial.';
  end if;
  update interno.usuarios_internos
     set senha_hash = extensions.crypt(p_senha, extensions.gen_salt('bf', 10)), tentativas_falhas = 0, bloqueado_ate = null
   where lower(email) = lower(btrim(p_email));
  if not found then raise exception 'Usuário do painel não encontrado.'; end if;
end;
$$;
revoke execute on function interno.definir_senha_painel(text, text) from public, anon, authenticated;
drop function if exists interno.validar_senha_painel(text);
