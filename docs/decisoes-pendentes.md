# Decisões pendentes

Regra do projeto: **não inventar**. Cada linha abaixo trava ou influencia código. Quando decidido, mover para "Decididas" e ajustar código/testes.

## Decididas

| # | Decisão | Quem / quando | Onde está refletida |
|---|---|---|---|
| D1 | **O candidato escolhe o Grupo** (e o Nível) | Responsável, 21/09/2026 | `inscricoes.grupo/nivel`, `cursos_aceitos` |
| D2 | **Plano Free do Supabase, sem Pro** (US$ 0). Decisão firme: não haverá plano Pro. | Responsável, 21/09/2026 | Riscos assumidos e mitigações em R1 a R5 (abaixo) |
| D3 | Foco atual: **formulário e cadastro**; demais módulos depois | Responsável, 21/09/2026 | escopo da Fase 1 |
| D4 | Identificação do candidato: **código por e-mail, sem senha** (proposta do assistente, aceita por "seguir como você deseja") | 21/09/2026 | Auth OTP; **exige SMTP próprio** (ver abaixo) |
| D5 | **Envio definitivo**: ao clicar em "Enviar solicitação" a inscrição fica selada; o candidato não altera nem apaga nada, apenas consulta (direito de acesso, LGPD art. 18); só a Comissão terá acesso, com auditoria. Antes do envio o candidato trabalha em **rascunho** e pode voltar depois. | Responsável, 21/09/2026 | `minha_inscricao_editavel_id()` (só `rascunho`), política de `candidatos`; resolve N4 |
| D6 | **Chave Pix da taxa: `pss2026comurg@comurg.com.br`** (e-mail) | Responsável, 21/09/2026 | `interno.configuracao` + `publico.dados_pagamento()`; **contradiz a minuta v2, item 4.9 (chave CNPJ)**, ver P2 |
| D7 | Nomes oficiais dos grupos: A "Analista de Projetos e Obras", B "Governança de Projetos", C "Analista de Licitações e Conformidade Processual" (edital, itens 3.2 a 3.4) | Lidos do edital | protótipo e app; resolve N6 |
| D8 | Lista de graduações do seed conferida **programaticamente contra o edital** (9 listas, 339 linhas, idênticas) | 21/09/2026 | `supabase/seed/gerar_cursos_aceitos.py` |
| D9 | **Sem plano Pro do Supabase** (reconfirmado). Se passar de ~100 candidatos, os arquivos vão para um bucket S3-compatível em nome da COMURG (conta a abrir); enquanto isso, o Supabase Storage segue como destino, atrás de uma camada única no código para trocar sem refazer telas. | Responsável, 21/09/2026 | `src/lib/armazenamento.ts` (comentário no topo) |
| D10 | **Motor de regras (pontuação da análise curricular) construído hoje**, em SQL no schema `interno`, com um **painel mínimo** para a Comissão ver o resultado por candidato | Responsável, 22/09/2026 | `supabase/migrations/20260922*`, `apps/portal-candidato/src/app/painel` |
| D11 | **Extração de documentos por IA usa a OpenAI** (não a Anthropic). O responsável já tem conta e vai gerar a chave. | Responsável, 22/09/2026 | `src/lib/openai.ts`, `src/app/api/extrair-documento`; **ainda sem a chave, código não testado (P6)** |
| D12 | A pontuação **precisava aparecer numa tela hoje**, mesmo sem o painel interno (app separado) existir ainda | Responsável, 22/09/2026 | painel roda dentro do mesmo app do portal, só para quem está na lista `interno.usuarios_internos`; ver P5 |
| D13 | **Login do painel reforçado**: e-mail + senha (conferidos sem abrir sessão) e só depois o código por e-mail — não é mais o login simples do candidato. Limite conhecido: ver P8. | Responsável, 22/09/2026 | `/painel/entrar`, `/api/painel/senha`, `painel.eh_membro` |
| D14 | **A IA passou a comparar, não só transcrever**: para cada documento, ela recebe o que o candidato declarou (curso, instituição, período etc.) e diz, campo a campo, se o documento confirma, contradiz ou não menciona — sempre citando o que o documento realmente diz. | Responsável, 22/09/2026 | `src/lib/openai.ts` (verificarDocumento), `painel.dados_declarados_documento` |
| D15 | **Documentos da análise curricular (diploma, pós/mestrado/doutorado, certificados, comprovantes de experiência, ART/RRT/acervo, declaração de liderança, histórico escolar, revalidação de diploma, tradução juramentada, currículo) só aceitam PDF.** Identidade, CPF, laudo PcD, autodeclaração racial, comprovante de Pix e requerimento de isenção continuam aceitando PDF/JPG/PNG. | Responsável, 22/09/2026 | migração `20260922130000_pdf_obrigatorio_analise_curricular.sql` (constraint no banco), `tipos-inscricao.ts:exigeSomentePdf` |

## Pendências novas (21/09/2026)

| # | Pergunta | Detalhe |
|---|---|---|
| P1 | **Critérios da isenção da taxa.** O edital **não define critérios objetivos**: 4.10 (requerimento fundamentado + documentação comprobatória, decisão motivada), 4.10.1 (sem documentação = indeferimento) e 4.10.3 (a COMURG **não** está obrigada às hipóteses da Lei 12.799/2013 e decide por razoabilidade e isonomia). | Sugestão: publicar uma lista fechada de situações aceitas (ex.: inscrição no CadÚnico, desemprego comprovado etc.) para evitar decisões arbitrárias e recursos. Decisão da Comissão/jurídico. |
| P2 | **Edital, item 4.9, ainda cita a chave CNPJ.** A versão anterior da minuta dizia "chave indicada na plataforma de inscrição". | Ajustar o edital para a chave nova (ou voltar ao texto "indicada na plataforma", que dispensa retificar se a chave mudar). Também revisar 4.9.4 (verificação da chave). |
| P3 | **Correção de erros depois do envio definitivo** (CPF digitado errado, arquivo trocado). Hoje ninguém corrige. | Definir um canal formal via Comissão (pedido justificado, com registro), coerente com 5.5.3. |
| P4 | Item 4.10 diz que o pedido de isenção é feito "exclusivamente pelo canal oficial de **e-mail**", mas o sistema recebe o pedido na plataforma. | Ajustar o edital (já era a pendência 3 do CLAUDE.md). |
| P5 | **O painel de hoje quebra o princípio 6 do CLAUDE.md** ("duas áreas separadas", app e subdomínio próprios, MFA obrigatório): por prazo, ele roda nas mesmas rotas e no mesmo login (código por e-mail) do portal do candidato, liberado só para quem está na tabela `interno.usuarios_internos`. Candidatos que não estão nessa lista recebem "Acesso restrito", mas a separação de fato (app/subdomínio/MFA) não existe ainda. | **Dívida técnica a resolver antes de dar acesso a mais gente da Comissão.** Para você testar hoje: faça login uma vez em `/entrar` com o e-mail que vai usar, me avise, e eu insiro esse e-mail em `interno.usuarios_internos`. |
| P6 | **Extração de documentos por IA não foi testada** (falta `OPENAI_API_KEY`, D11). O código está pronto (`src/lib/openai.ts`, rota `/api/extrair-documento`, botão "Analisar com IA" no painel) mas o formato exato da resposta da OpenAI só foi conferido pela documentação, não por uma chamada real. | Testar assim que houver a chave; corrigir o parsing se o formato vier diferente do esperado. |
| P7 | **Correlação de títulos e cursos com as atribuições do Grupo** (Anexo I, itens 1 e 2: "diretamente relacionados") não é verificada pelo motor — ele pontua e sinaliza "exige confirmação da Comissão" em cada item. Da mesma forma, o **catálogo de cursos pontuáveis** (Anexo I, item 2.1) é comparado por trecho de texto (aproximado); cursos fora dele pontuam do mesmo jeito, só com a sinalização "fora do catálogo". | Consistente com o edital ("lista exemplificativa... mediante deliberação motivada da Comissão", item 2.1) — decisão de correlação continua sempre humana. Nenhuma ação necessária, só ciência. |
| P8 | **O login por senha do painel (D13) tem um contorno conhecido:** a senha só é exigida em `/painel/entrar`. Se alguém souber o e-mail de um integrante da Comissão e tiver acesso à caixa de entrada dele, consegue pedir um código pela tela comum `/entrar` (a do candidato) e, ao validar, chega numa sessão que passa igual no `/painel` — porque o painel só confere "está na lista", não "entrou pela porta com senha". Isso porque o Supabase não distingue, na sessão final, se ela veio de um fluxo ou de outro. | Aceitável para uma lista pequena e de confiança (hoje 2 contas), mas não é uma trava de verdade. Fechar direito exigiria checar no `/painel` como a sessão foi criada (ou separar os dois logins de fato, como pede o princípio 6 do CLAUDE.md). |

## Novas, surgidas ao construir a Fase 1

| # | Pergunta | Impacto | Sugestão |
|---|---|---|---|
| N1 | **Horário exato** de abertura e encerramento (o edital só traz datas) | `interno.configuracao` (hoje 24/09 00:00 e 07/10 23:59:59, horário de Brasília) | Confirmar com a Comissão |
| N2 | **SMTP para e-mails de login**: qual conta/domínio envia? (Microsoft 365/Google da COMURG ou um serviço como Resend, com DNS do domínio) | Sem isso nenhum candidato recebe o código | Definir antes de 24/09 |
| N3 | **Limite de tamanho por arquivo** (hoje 10 MB no protótipo, no banco e no bucket) | Storage e UX | Manter 10 MB; PDFs escaneados costumam caber |
| N5 | **Retenção e descarte** dos dados e da auditoria (LGPD) | A auditoria hoje é imutável; descarte exigirá procedimento próprio | Definir com o jurídico/DPO |

## Riscos assumidos por ficar no plano Free (D2)

Valores do Free conferidos em supabase.com/pricing em 21/09/2026: banco 500 MB, **arquivos 1 GB**, tráfego de saída **5 GB/mês**, **sem backups**, pausa após 1 semana de inatividade.

| # | Risco | Consequência | Mitigação prevista | Situação |
|---|---|---|---|---|
| R1 | **Sem backup** do banco nem dos arquivos | Perda irreversível de dados de candidatos (erro humano, falha do serviço) | Cópia própria, **criptografada**, em local da COMURG, agendada (banco + arquivos). Exige a senha do banco, que fica só em `.env` local | A fazer; **precisa de decisão do destino da cópia** |
| R2 | **1 GB de arquivos** (cerca de 50 candidatos com ~20 MB cada, estimativa a validar) | Quando lotar, os uploads passam a falhar e candidatos ficam sem conseguir se inscrever (problema de isonomia) | Reduzir o limite por arquivo, orientar PDFs leves, e se o número de candidatos passar de ~100, **guardar arquivos fora do Supabase** (armazenamento da COMURG ou serviço S3-compatível) | **Depende do nº de candidatos esperado** |
| R3 | **Pausa por inatividade** (1 semana) | Portal fora do ar sem aviso | Agendar uma chamada diária ao banco (keep-alive) e monitorar | A fazer |
| R4 | **5 GB/mês de tráfego** | Comissão abrindo os mesmos arquivos várias vezes consome a cota | Links assinados de curta duração, miniaturas e cache; monitorar consumo | A fazer na fase do painel |
| R5 | **"Prevent use of leaked passwords" (checagem HaveIBeenPwned) não disponível no Free** — `get_advisors` acusa `auth_leaked_password_protection` (WARN); a tela de "Attack Protection" mostra "DISABLED" e manda configurar no provedor de e-mail, mas o toggle de verdade não fica disponível no plano Free | Uma senha do painel vazada em outro serviço e reaproveitada aqui não seria bloqueada no cadastro/troca | Nenhuma (depende do Pro). Mitigado por hoje só existirem 2 contas, com senhas fortes e aleatórias geradas por mim (não reaproveitadas), e pelo login do painel exigir também o código por e-mail (D13) — uma senha vazada sozinha não entra | **Risco aceito**, responsável, 22/09/2026 — revisitar se e quando entrar mais gente na Comissão com senha própria |

O que **não** depende do plano e já está pronto: RLS em todas as tabelas, permissões por coluna, inscrição selada após o envio, trava de prazo no servidor, bucket privado, auditoria imutável e schema `interno` fora da API.


Continuam em aberto; só afetam as fases seguintes (motor de regras, pagamentos, entrevista), exceto onde indicado.

1. Faixas de experiência com limites sobrepostos (Anexo I, item 3) e arredondamento de meses. *(O motor de regras de hoje assumiu a convenção (0,12], (12,36], (36,60], (60,∞) meses — ver D10. Confirmar com a Comissão.)*
2. **Isenção × prazo de pagamento**: decisão da isenção sai em 09/10, inscrições encerram em 07/10 e o item 4.9.5 só aceita comprovante dentro do período. *(Já afeta a Fase 1: hoje o status é `aguardando_isencao`, sem janela extra de pagamento.)*
3. Pedido de isenção por e-mail (texto do edital) versus pela plataforma (implementado assim).
4. Equivalência da pós no Pleno (5 anos substituem a pós, mas o mínimo já é 4). *(O motor de hoje assumiu: título OU 5 anos de experiência OU, só no Grupo B, certificação PMP/PgMP/PRINCE2/IPMA ativa — qualquer um libera a habilitação, sem descontar pontos do título. Ver D10. Confirmar com a Comissão.)*
5. "Tecnologia da Informação" no Grupo B versus exclusão de tecnólogo (5.1.6). *(Hoje a lista aceita o curso pelo nome; o grau tecnológico é sinalizado, não bloqueado.)*
6. Cadastro de reserva do Pleno: 5 por grupo (tabela 2.1) ou 20 no total (item 11.1).
7. Cláusula do edital sobre sistema assistido por IA. *(O texto de ciência no formulário é provisório.)*
8. Mestrado/doutorado em áreas afins e "áreas diretamente relacionadas".
9. Conferência do Pix: quem concilia com o extrato, em que formato; CPF mascarado.
10. ~~Identidade do candidato (e-mail/senha ou gov.br)~~ → ver D4.
11. Banca da entrevista vê a pontuação curricular?
12. Cada avaliador lança a própria nota no sistema?
13. Ficha do Anexo II, Parte 2 (notas 1 a 10 em competências de peso 5).
14. Rigor formal dos documentos (CPF no diploma, carimbo do CNPJ, assinatura digital).
15. "Cancelamento automático" por Pix divergente (4.9.4) versus decisão fundamentada (1.6) e LGPD art. 20. *(Fase 1 não cancela nada automaticamente.)*
16. Verificações externas (e-MEC, Diplomas Digitais do MEC): manuais ou automatizadas; volume de candidatos.
