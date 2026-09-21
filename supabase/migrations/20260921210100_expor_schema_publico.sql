-- Fase 1 · Expõe na API (PostgREST) apenas o schema `publico`. O schema `interno` NUNCA entra aqui.
-- Reversão: supabase/rollback/20260921210100_expor_schema_publico.down.sql
alter role authenticator set pgrst.db_schemas = 'publico, graphql_public';
notify pgrst, 'reload config';
notify pgrst, 'reload schema';
