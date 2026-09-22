# Publicar o portal do candidato no Netlify

**Status: publicado.** Site no ar em **https://pss-comurg-2026.netlify.app** (conta Netlify da COMURG, equipe
`opevcomurg`), deploy feito em 22/09/2026.

## O que foi feito

1. **Repositório no GitHub:** `https://github.com/josesilva422/fomr_comurg` (o responsável já tinha criado; eu só
   adicionei como remoto e enviei os commits — `git remote add origin ... && git push -u origin main`).
2. **Site criado no Netlify** via ferramenta (MCP), na equipe `opevcomurg`, com o nome `pss-comurg-2026`.
3. **Variáveis de ambiente** (Site settings → Environment variables):

   | Nome | Valor | Quem colocou |
   |---|---|---|
   | `NEXT_PUBLIC_SUPABASE_URL` | `https://uwtnmzlbgbufiqzsxjuz.supabase.co` | eu (público, protegido por RLS) |
   | `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | `sb_publishable__SK4LFSjraphKwxn3jeS6Q_7AlSP0RP` | eu (público) |
   | `OPENAI_EXTRACTION_MODEL` | `gpt-4o-mini` | eu (não é segredo) |
   | `OPENAI_API_KEY` | (chave real) | **o responsável**, direto no painel do Netlify — não deixo chave de API em nenhum serviço externo por mim mesmo |
   | `SECRETS_SCAN_OMIT_PATHS` | `.netlify/.next/cache/**` | eu (ver "Problema 3" abaixo) |

4. **Deploy:** feito por upload direto (não é integração contínua com o GitHub — ver "Diferença do plano original"
   abaixo). Publicado com `npx @netlify/mcp@latest --site-id <id> --proxy-path <url>`, rodado a partir da raiz do
   repositório.
5. **Acesso público confirmado:** `requiresSSOTeamLogin` estava `true` por padrão num site novo (proteção do
   próprio Netlify contra publicação acidental por um agente); o responsável desativou pelo painel
   (Site configuration → Sharing/Visitor access) antes do primeiro deploy funcionar.

## Diferença do plano original

O plano original (abaixo, mantido como referência) previa conectar o Netlify direto no repositório GitHub
("Import an existing project"), com deploy automático a cada `git push`. A ferramenta de deploy disponível nesta
sessão não expõe essa integração contínua — ela faz **upload direto do diretório local**, builda no Netlify e
publica. Funciona igual para o candidato final, mas **não redeploya sozinho a cada push**: para atualizar o site
depois de uma mudança no código, é preciso rodar o deploy de novo (por mim, nesta ferramenta, ou você mesmo pelo
painel do Netlify arrastando uma pasta, ou conectando o repositório pela import de GitHub manualmente).

**Se quiser deploy automático a cada push:** no painel do Netlify → o site `pss-comurg-2026` → **Site
configuration → Build & deploy → Link repository**, e escolher o repositório `josesilva422/fomr_comurg`. Depois
disso, todo `git push` na `main` publica sozinho.

## Três problemas reais encontrados e corrigidos no caminho

1. **`netlify.toml` mal posicionado.** Estava dentro de `apps/portal-candidato/netlify.toml`, mas com
   `base = "apps/portal-candidato"` dentro dele — isso faria o Netlify procurar
   `apps/portal-candidato/apps/portal-candidato`, que não existe. Corrigido: movido para a raiz do repositório
   (padrão do Netlify para monorepo: o arquivo fica na raiz, e o campo `base` dentro dele aponta pro
   subdiretório do app).
2. **Payload de deploy gigante (~810 MB).** A ferramenta de deploy usada zipa o diretório inteiro e **não
   respeita `.gitignore` nem `.netlifyignore`** — então `node_modules` e `.next` (que juntos passavam de 800 MB)
   iam junto, e isso derrubava o envio com "500 Internal Server Error". Corrigido removendo `node_modules` e
   `.next` do disco antes do deploy (o Netlify instala e builda do zero no lado dele de qualquer forma, então
   isso não afeta o resultado — só precisa rodar `npm install` de novo depois, pra voltar a desenvolver local).
3. **Scanner de segredos do Netlify bloqueando o build.** O cache do Turbopack (motor de build do Next.js),
   gerado dentro de `.netlify/.next/cache/`, guarda um dump interno que às vezes inclui o valor de variáveis de
   ambiente do servidor — nesse caso, a `OPENAI_API_KEY`. O Netlify escaneia o resultado do build à procura de
   segredos vazados e **recusa publicar** se encontrar algo, mesmo sendo um artefato de cache interno (não é o
   que fica exposto ao público). Resolvido com a variável de ambiente `SECRETS_SCAN_OMIT_PATHS =
   .netlify/.next/cache/**`, que exclui só esse diretório de cache da varredura — a proteção continua ativa
   para tudo o mais.

## Antes de divulgar o link para candidatos reais

- [ ] SMTP de login configurado (ver `configurar-email-login.md`) — já testado e funcionando
- [ ] Horário de abertura/encerramento conferido em `interno.configuracao` (hoje está adiantado pra permitir
      teste; **precisa voltar para 24/09/2026 00:00 -03 antes do lançamento real**)
- [ ] Apagar os arquivos de teste do bucket `documentos` (Storage, painel do Supabase)
- [ ] Testar o fluxo completo uma vez no link publicado (feito parcialmente: página inicial e login carregando
      sem erro; falta um teste ponta a ponta completo, com envio de inscrição, no ambiente publicado)
- [ ] Domínio próprio (hoje é `pss-comurg-2026.netlify.app`) — ver seção abaixo

## Apontar o domínio (quando o DNS estiver liberado)

Em **Domain settings → Add a domain**, adicione `inscricao.<dominio-da-comurg>`. O Netlify mostra um registro
CNAME (ou os IPs, se preferir A record) para cadastrar no painel de DNS que administra o domínio da COMURG. A
propagação costuma levar de minutos a algumas horas.

---

## Plano original (histórico, não foi o que aconteceu — ver acima)

<details>
<summary>Passos previstos antes de começar (import via GitHub, deploy contínuo)</summary>

### 1. Criar o repositório e enviar o código (uma vez)

```bash
gh repo create comurg-pss-2026 --private --source=. --remote=origin
git push -u origin main
```

### 2. Conectar no Netlify

1. No painel do Netlify: **Add new site → Import an existing project → GitHub**.
2. Escolher o repositório.
3. O Netlify leria o `netlify.toml` e detectaria o Next.js automaticamente (plugin `@netlify/plugin-nextjs`).
4. Configurar as variáveis de ambiente.
5. **Deploy site**.

</details>
