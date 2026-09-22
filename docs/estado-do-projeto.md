# Estado do projeto — ponto de retomada

Este arquivo existe para o caso da conversa com o assistente ser resumida ou reiniciada. Leia isto primeiro;
os outros arquivos de `docs/` têm os detalhes de cada decisão. **Sempre confira a data da última atualização
no topo e o `git log` — este arquivo pode ficar desatualizado se eu esquecer de mexer nele.**

**Última atualização:** 22/09/2026, tarde. **Prazo:** entrega do projeto "amanhã" (combinado em 22/09).
**Site publicado:** https://pss-comurg-2026.netlify.app (ver `docs/publicar-netlify.md` para detalhes e os 3
problemas resolvidos no primeiro deploy).

## O que é este projeto

Sistema de inscrição do PSS COMURG 2026 (contratação de Analistas de Governança). Regras em `CLAUDE.md`
(raiz do repo) e no edital em `docs/Minuta_Edital_PSS_COMURG_2026_v2.docx`. **O edital manda; se `CLAUDE.md`
divergir dele, o edital vence.**

## Onde está tudo

- **Repositório:** `C:\Users\joses\OneDrive\Documentos\form_minuta_COMURG`, enviado para
  `https://github.com/josesilva422/fomr_comurg` (remoto `origin`, branch `main`).
- **Site publicado:** `https://pss-comurg-2026.netlify.app` (conta Netlify da COMURG, equipe `opevcomurg`).
  Deploy feito por upload direto (não é deploy automático a cada push — ver `docs/publicar-netlify.md` se quiser
  configurar isso).
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

6. **Importar currículo com preenchimento automático por IA** (`ImportarCurriculo.tsx`, topo da etapa
   Formação): a pessoa envia o currículo (PDF/JPG/PNG) e a IA (`lerCurriculo()` em `src/lib/openai.ts`)
   devolve graduação/títulos/cursos/vínculos encontrados. Isso só **pré-preenche cartões editáveis** com o
   selo "Do currículo — confira antes de salvar"; nada vira `titulos_declarados`/`cursos_declarados`/
   `vinculos_declarados` de verdade até a pessoa clicar em "Salvar" em cada cartão, um por um (se o currículo
   tem 8 cursos, aparecem 8 cartões separados). O próprio arquivo do currículo é salvo como documento normal
   (`curriculo_anexo_v`), contando como o envio do Anexo V. Testado de ponta a ponta com currículo fictício
   sintético: 2 títulos, 8 cursos (1 certificação com credencial/código), 2 vínculos, todos os campos certos.
   Bug encontrado e corrigido no teste: Strict Mode do React duplicava os cartões de vínculo (useEffect
   rodando duas vezes) — corrigido com guarda por identidade de referência (`useRef`) em `PassoExperiencia.tsx`.

## Dados de teste

Os candidatos demo do painel (Fernanda, Rafael, Camila) e o candidato de teste do currículo
(`teste.cv@comurg.invalid`) **já foram apagados** (candidatos, inscrições, documentos e usuários de auth) e a
data de abertura das inscrições (`interno.configuracao.inscricoes_abertura`) foi **restaurada para
24/09/2026 00:00 -03** (estava em 20/09 só para permitir testar antes da data real — a partir de agora o
formulário volta a bloquear preenchimento antes dessa data, então testes futuros no wizard precisam mexer
nessa config de novo, temporariamente).

Ainda sobraram uns **19 arquivos pequenos de teste** no bucket `documentos` do Storage — não dá para apagar
por SQL (`storage.objects` não limpa o blob por trás de forma confiável por aqui); precisa ser pelo painel do
Supabase (Storage → bucket `documentos` → selecionar e excluir).

## Dívidas técnicas conhecidas (não escondidas, documentadas)

- **P5:** o painel roda nas mesmas rotas/app do portal do candidato. O CLAUDE.md pede dois apps/subdomínios
  separados com MFA — isso não existe ainda.
- **P8:** o login por senha do painel não é uma trava criptográfica de verdade — alguém com acesso ao e-mail
  de um integrante da Comissão ainda consegue chegar ao painel pelo login comum do candidato (sem senha). Ver
  detalhe em `decisoes-pendentes.md`.
- **R1-R4:** riscos do plano Free do Supabase (sem backup, 1 GB de arquivos, pausa por inatividade) — ver
  `decisoes-pendentes.md`.

## Ainda faltando para o lançamento de verdade

- **Testar o fluxo completo no site publicado** (só confirmei página inicial e login carregando sem erro; falta
  um teste ponta a ponta com envio de inscrição de verdade em `pss-comurg-2026.netlify.app`).
- Domínio próprio (hoje é `pss-comurg-2026.netlify.app`).
- Apagar os ~19 arquivos de teste que sobraram no Storage (só dá pelo painel do Supabase, ver acima).
- **Confirmar a data de abertura das inscrições antes de divulgar o link**: `interno.configuracao.inscricoes_abertura`
  está em `2026-09-20T00:00:00-03:00` (adiantada de propósito para permitir testar); precisa voltar para
  `2026-09-24T00:00:00-03:00` (data real do edital) antes do lançamento — não esquecer.
