# Publicar o portal do candidato no Netlify

Passos que só você consegue fazer (exigem login seu no GitHub e no Netlify). Eu preparo tudo até aqui; quando quiser
seguir, me avise e eu confirmo cada comando antes de rodar (principalmente o `git push`, que publica o código).

## 1. Criar o repositório e enviar o código (uma vez)

O projeto já é um repositório Git local, com todos os commits prontos, mas **nada foi enviado a lugar nenhum ainda**.

```bash
gh repo create comurg-pss-2026 --private --source=. --remote=origin
git push -u origin main
```

Isso cria um repositório **privado** na sua conta do GitHub (`gh` precisa estar autenticado; rode `gh auth status`
para conferir). Se preferir um nome diferente ou uma organização da COMURG em vez da sua conta pessoal, me diga antes.

## 2. Conectar no Netlify

1. No painel do Netlify (você usa o Pro): **Add new site → Import an existing project → GitHub**.
2. Escolha o repositório `comurg-pss-2026`.
3. O Netlify já lê o `apps/portal-candidato/netlify.toml` e detecta o Next.js automaticamente
   (plugin `@netlify/plugin-nextjs`). Não precisa mudar os campos de build.
4. Em **Site settings → Environment variables**, adicione:

   | Nome | Valor |
   |---|---|
   | `NEXT_PUBLIC_SUPABASE_URL` | `https://uwtnmzlbgbufiqzsxjuz.supabase.co` |
   | `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | `sb_publishable__SK4LFSjraphKwxn3jeS6Q_7AlSP0RP` |

   São valores públicos (a proteção fica no RLS do banco), mas ficam fora do repositório para não prender o código a
   um projeto Supabase específico.
5. Clique em **Deploy site**. O Netlify gera um link `algo-aleatorio.netlify.app` — já é público e funcional.

## 3. Apontar o domínio (quando o DNS estiver liberado)

Em **Domain settings → Add a domain**, adicione `inscricao.<dominio-da-comurg>`. O Netlify mostra um registro CNAME
(ou os IPs, se preferir A record) para você cadastrar no painel de DNS que administra o domínio da COMURG. A propagação
costuma levar de minutos a algumas horas.

## 4. Antes de divulgar o link para candidatos reais

- [ ] SMTP de login configurado (ver `configurar-email-login.md`) — sem isso ninguém consegue entrar
- [ ] Horário de abertura/encerramento conferido em `interno.configuracao`
- [ ] Os 10 arquivos de teste apagados do bucket `documentos` (Storage, no painel do Supabase)
- [ ] Testar o fluxo completo uma vez no link publicado (não só em localhost)
