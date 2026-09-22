alter role authenticator set pgrst.db_schemas = 'publico, graphql_public';
notify pgrst, 'reload config';
notify pgrst, 'reload schema';
