-- Fase 2 · Correção: schema `painel` tinha USAGE só para `authenticated`, faltando para `anon`.
-- A etapa 1 do login do painel (checar e-mail+senha) roda sem sessão (papel anon), e chamadas em
-- painel.* ficavam bloqueadas com "permission denied for schema painel" antes mesmo de o RLS entrar
-- em jogo. Objeto tem grant, mas faltava a permissão no schema (USAGE), que é hierárquica no Postgres.
-- Reversão: supabase/rollback/20260922110100_corrige_usage_schema_painel_anon.down.sql
grant usage on schema painel to anon;
