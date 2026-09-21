# Fase 1 · Backend do formulário de inscrição

Escopo desta fase: **cadastro do candidato + formulário de inscrição + documentos + envio**.
Fica para depois: painel interno, pagamentos/conciliação, extração por IA, motor de regras, resultados, recursos, entrevista.

## Projeto Supabase

| Item | Valor |
|---|---|
| Nome / ref | `pss_comurg_2026` / `uwtnmzlbgbufiqzsxjuz` |
| Organização | Comurg |
| Região | `sa-east-1` (São Paulo) |
| Plano | **Free (US$ 0)**. Ver "Limites do plano gratuito" abaixo |

Os projetos `gestao_ativos_comurg` e `pesquisa_satisfacao_comurg` (mesma organização) **não** foram tocados.

## Como a segurança funciona

- **Dois schemas.** `publico` (candidato lê e escreve a própria inscrição) e `interno` (configuração e auditoria). `interno` **não** é exposto na API e não tem nenhum GRANT para `anon`/`authenticated`.
- **RLS em todas as tabelas**, e permissões por coluna: o candidato **não consegue** alterar `status`, `submetida_em`, `declaracoes_aceitas_em`, `user_id` nem `email`.
- **Trava de prazo no banco** (itens 5.5.3 e 9.4): fora do período, qualquer inclusão, alteração ou remoção feita por conta de candidato é recusada, inclusive envio de arquivo. O candidato continua *lendo* o que enviou.
- **Documentos append-only.** Não se apaga nem sobrescreve: "remover" marca `ativo = false` (o servidor grava `removido_em`); não dá para reativar. No Storage o candidato só envia e lê, e só na própria pasta `{inscricao_id}/...`.
- **Auditoria imutável** (`interno.auditoria`): registra ator, ação, antes/depois e IP de cada mudança; UPDATE, DELETE e TRUNCATE são bloqueados.
- **Regras de envio no servidor**: `publico.verificar_inscricao()` devolve as pendências (código, mensagem, etapa do formulário) e `publico.submeter_inscricao()` só conclui se não houver nenhuma. O frontend apenas exibe.

Testes: `supabase/tests/fase1_seguranca.test.sql` (89 verificações, roda numa transação que é desfeita; **todas passaram** em 21/09/2026).

## Fluxo do candidato (para o frontend)

1. Login por **código enviado ao e-mail** (`signInWithOtp`), sem senha.
2. `insert` em `publico.candidatos` (nome, cpf só com dígitos, telefone só com dígitos, nascimento, nacionalidade). O e-mail vem da conta; a inscrição (`publico.inscricoes`) é criada automaticamente.
3. `update` em `publico.inscricoes` conforme o candidato avança; `insert`/`update`/`delete` em `titulos_declarados`, `cursos_declarados`, `vinculos_declarados`.
4. Upload do arquivo em `documentos/{inscricao_id}/{tipo}/{uuid}.{ext}` (Storage) e, em seguida, `insert` em `publico.documentos` com o caminho, o SHA-256 (calculado no navegador) e o tamanho.
5. `rpc('verificar_inscricao')` mostra as pendências; `rpc('aceitar_declaracoes')`; `rpc('submeter_inscricao')`.

Meses de experiência são gravados como o **primeiro dia do mês** (`2020-01-01`).

## O que ainda precisa ser feito no painel do Supabase (não dá para automatizar daqui)

1. **Expor o schema `publico` na API.** Settings → Data API → *Exposed schemas* → adicionar `publico` (manter `graphql_public`; **não** adicionar `interno`). Hoje a API responde `Invalid schema: publico`.
2. **E-mail de login.** O envio embutido do Supabase só entrega para membros da organização (candidatos receberiam "Email address not authorized"). É obrigatório configurar **SMTP próprio** (Authentication → Emails → SMTP Settings) e trocar o modelo do e-mail de "Magic Link" para mostrar o código `{{ .Token }}`.
3. Authentication → *Sign In / Providers*: manter e-mail habilitado, **desativar** login anônimo, e conferir o limite de envios por hora.
4. Antes de abrir para candidatos reais: **plano Pro** (backups, sem pausa por inatividade). Ver abaixo.

## Limites do plano gratuito (verificados em supabase.com/pricing em 21/09/2026)

| Recurso | Free | Pro (US$ 25/mês) |
|---|---|---|
| Banco de dados | 500 MB | 8 GB |
| Arquivos (Storage) | **1 GB** | 100 GB |
| Tráfego de saída (egress) | **5 GB/mês** | 250 GB |
| Usuários ativos/mês | 50.000 | 100.000 |
| Backups | **não inclui** | diários, 7 dias |
| Pausa por inatividade | **após 1 semana** | nunca |

Estimativa (premissa: ~10 arquivos por candidato, ~2 MB cada, o que é um chute a validar): cerca de 20 MB por candidato, então **1 GB comporta ~50 candidatos**. A Comissão abrir os mesmos arquivos algumas vezes consome o egress rápido. O banco (500 MB) não é o gargalo.
**Conclusão:** o gratuito serve para desenvolver e testar; para o período real de inscrição é preciso Pro, ou o projeto pausa/enche e não há backup de dados sensíveis (LGPD).

## Acréscimos ao modelo do CLAUDE.md

O rascunho da seção 7 não previa onde guardar o que o formulário coleta. Foram adicionados:
`titulos_declarados`, `cursos_declarados` (pós/mestrado/doutorado e cursos/certificações), campos de graduação, reservas e isenção em `inscricoes`, `cursos_aceitos` (referência), `interno.configuracao` (datas do período) e `interno.auditoria`.
`concomitante` **não** foi gravado em `vinculos_declarados`: é derivado da sobreposição dos períodos (o motor de regras calcula).
Ficam para as próximas fases: `pagamentos`, `isencoes` (decisão), `verificacoes_externas`, `extracoes`, `avaliacoes_curriculares`, `decisoes_revisao`, `entrevistas`, `fichas_avaliador`, `usuarios_internos`, `resultados_candidato`, `recursos`.

## Migrações

Fonte da verdade: `supabase/migrations/*.sql`; reversão de cada uma em `supabase/rollback/*.down.sql` (só para desenvolvimento).
Foram aplicadas ao projeto pelo assistente do Supabase, então os números de versão registrados no banco diferem dos nomes dos arquivos; o conteúdo é o mesmo. Antes de usar `supabase db push`, alinhar o histórico (`supabase migration repair`).
O seed `cursos_aceitos` (339 linhas) é gerado por `supabase/seed/gerar_cursos_aceitos.py` a partir do CLAUDE.md, **e precisa ser conferido contra o edital**.
