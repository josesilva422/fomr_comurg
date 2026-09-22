# Estado do projeto — ponto de retomada

Este arquivo existe para o caso da conversa com o assistente ser resumida ou reiniciada. Leia isto primeiro;
os outros arquivos de `docs/` têm os detalhes de cada decisão. **Sempre confira a data da última atualização
no topo e o `git log` — este arquivo pode ficar desatualizado se eu esquecer de mexer nele.**

**Última atualização:** 22/09/2026, cerca de 23h. **Prazo:** entrega do projeto "amanhã" (combinado em 22/09).

## O que é este projeto

Sistema de inscrição do PSS COMURG 2026 (contratação de Analistas de Governança). Regras em `CLAUDE.md`
(raiz do repo) e no edital em `docs/Minuta_Edital_PSS_COMURG_2026_v2.docx`. **O edital manda; se `CLAUDE.md`
divergir dele, o edital vence.**

## Onde está tudo

- **Repositório:** local, em `C:\Users\joses\OneDrive\Documentos\form_minuta_COMURG`. Git iniciado, **nada
  enviado a nenhum remoto ainda** (sem GitHub, sem Netlify publicado — decisão explícita do responsável de
  não publicar por enquanto).
- **App do candidato + painel da Comissão:** `apps/portal-candidato` (Next.js 16, TypeScript, App Router).
  Roda com `npm run dev` **de dentro dessa pasta** (não da raiz).
- **Banco:** Supabase, projeto `pss_comurg_2026` (ref `uwtnmzlbgbufiqzsxjuz`), organização "Comurg", região
  `sa-east-1`, **plano Free** (decisão D2/D9 — sem Pro).
- **Migrações:** `supabase/migrations/*.sql` (fonte da verdade, aplicadas manualmente via MCP do Supabase
  nesta conversa — os nomes de arquivo têm timestamp mas a aplicação real ficou fora de ordem cronológica de
  commit; antes de usar `supabase db push` teria que rodar `supabase migration repair`).
- **Decisões e pendências:** `docs/decisoes-pendentes.md` (D1–D14 decididas, P1–P8 + N1-N3/N5 pendências,
  mais a lista herdada do CLAUDE.md). **Leia esse arquivo inteiro antes de inventar qualquer regra nova.**
- **Fase 1 (backend/RLS):** `docs/fase1-backend.md`. **Fase 2 (motor de regras/painel):**
  `docs/fase2-motor-e-painel.md`.

## O que está pronto e testado

1. **Portal do candidato, as 7 etapas completas**, ponta a ponta, incluindo o envio real (`submeter_inscricao`)
   que sela a inscrição — testei criando um candidato de teste, passando pelas 7 etapas no navegador e
   confirmando que a inscrição fica travada mesmo depois de recarregar a página.
2. **Login do candidato:** só e-mail + código (sem senha), via Supabase Auth OTP. **SMTP configurado**
   (Umbler) e os dois modelos de e-mail (`Confirm signup` e `Magic Link`) já têm `{{ .Token }}` — testado
   pelo responsável, chegou certo.
3. **Motor de regras** (`interno.calcular_avaliacao`, SQL): habilitação + pontuação do Anexo I (formação
   adicional, cursos/certificações, experiência). Testado com o exemplo do item 5.4.2 do edital (deu 42
   meses, correto) e com 3 candidatos de perfis diferentes.
4. **Painel da Comissão** (`/painel`, dentro do mesmo app — ver dívida técnica P5 abaixo):
   - Login **separado** do candidato: `/painel/entrar`, e-mail + senha + depois código (`/api/painel/senha`
     confere a senha sem abrir sessão, só then dispara o OTP). Ver limite conhecido em **P8**.
   - Lista com filtros (habilitado/inabilitado, Grupo, Nível, "atinge 35 pts da entrevista") e busca.
   - Página de detalhe por candidato, com tópicos separados (Graduação, Pós-graduação, Cursos, Experiência),
     cada motivo de pontuação/rejeição explicado, citando o item do edital.
   - Link "Painel da Comissão" no cabeçalho do portal, só renderizado no servidor para quem tem permissão
     (não aparece no HTML de quem não tem — testado sem sessão).
   - **Verificação de documentos por IA (OpenAI, não Anthropic — decisão do responsável):** para cada
     documento, a IA recebe o que foi declarado e diz, campo a campo, se o documento confirma, contradiz ou
     não menciona — nunca decide sozinha. Chave já configurada e testada (`OPENAI_API_KEY` em
     `apps/portal-candidato/.env.local`, fora do Git).
5. **Contas do painel liberadas** (`interno.usuarios_internos`): `josegabrielpo422@gmail.com` e
   `pss2026comurg@comurg.com.br`, ambas com senha definida (o responsável tem as senhas; se perdidas, é só
   pedir para eu resetar via SQL — `extensions.crypt(...)` em `auth.users`, não fica escrito em nenhum arquivo
   por segurança).

## Dados de teste ainda no banco (apagar antes de ir para produção)

- 3 candidatos demo para exercitar o painel: **Fernanda Lima Costa** (habilitada, 47 pts), **Rafael Souza
  Andrade** (habilitado, 7 pts), **Camila Ribeiro Martins** (inabilitada, 0 pts) — e-mails `demo.*@teste.invalid`.
- Uns 10 arquivos pequenos de teste no bucket `documentos` do Storage (não dá para apagar por SQL; é pelo
  painel do Supabase).

## Pedido em andamento (ainda não implementado)

**Importar currículo com preenchimento automático por IA.** O responsável perguntou a complexidade antes de eu
começar; combinamos que:
- É viável e não é um risco de segurança grande (fica do lado do candidato, não mexe em dado de outro usuário).
- **Não é pequeno**: precisa de (1) campo de upload do currículo (o tipo `curriculo_anexo_v` já existe no
  banco), (2) a IA lendo o PDF e montando uma lista de formação/experiência/cursos encontrados, (3) **uma
  tela de conferência obrigatória** antes de qualquer dado virar `titulos_declarados`/`cursos_declarados`/
  `vinculos_declarados` de verdade — currículo é texto livre, a IA vai errar de vez em quando, e o princípio
  do projeto é decisão sempre humana, nunca preenchimento silencioso.
- Ainda não comecei a construir. Se retomar isso, seguir o padrão já usado em `src/lib/openai.ts` (Responses
  API, `json_schema` estrito) e nos repetidores de Formação/Experiência (`apps/portal-candidato/src/app/inscricao/`).

## Dívidas técnicas conhecidas (não escondidas, documentadas)

- **P5:** o painel roda nas mesmas rotas/app do portal do candidato. O CLAUDE.md pede dois apps/subdomínios
  separados com MFA — isso não existe ainda.
- **P8:** o login por senha do painel não é uma trava criptográfica de verdade — alguém com acesso ao e-mail
  de um integrante da Comissão ainda consegue chegar ao painel pelo login comum do candidato (sem senha). Ver
  detalhe em `decisoes-pendentes.md`.
- **R1-R4:** riscos do plano Free do Supabase (sem backup, 1 GB de arquivos, pausa por inatividade) — ver
  `decisoes-pendentes.md`.

## Ainda faltando para o lançamento de verdade

- Publicar (Netlify) — preparado em `docs/publicar-netlify.md`, mas **não executado** (aguardando autorização).
- Domínio próprio (hoje seria um `*.netlify.app`).
- Apagar os dados de teste (candidatos demo + arquivos de teste no Storage).
- Confirmar horário exato de abertura/encerramento (`interno.configuracao`) — hoje é uma suposição.
