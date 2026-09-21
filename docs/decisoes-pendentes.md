# Decisões pendentes

Regra do projeto: **não inventar**. Cada linha abaixo trava ou influencia código. Quando decidido, mover para "Decididas" e ajustar código/testes.

## Decididas

| # | Decisão | Quem / quando | Onde está refletida |
|---|---|---|---|
| D1 | **O candidato escolhe o Grupo** (e o Nível) | Responsável, 21/09/2026 | `inscricoes.grupo/nivel`, `cursos_aceitos` |
| D2 | Custo: **Supabase gratuito por ora** (US$ 0) | Responsável, 21/09/2026 | ver `fase1-backend.md` (limites e quando migrar para Pro) |
| D3 | Foco atual: **formulário e cadastro**; demais módulos depois | Responsável, 21/09/2026 | escopo da Fase 1 |
| D4 | Identificação do candidato: **código por e-mail, sem senha** (proposta do assistente, aceita por "seguir como você deseja") | 21/09/2026 | Auth OTP; **exige SMTP próprio** (ver abaixo) |

## Novas, surgidas ao construir a Fase 1

| # | Pergunta | Impacto | Sugestão |
|---|---|---|---|
| N1 | **Horário exato** de abertura e encerramento (o edital só traz datas) | `interno.configuracao` (hoje 24/09 00:00 e 07/10 23:59:59, horário de Brasília) | Confirmar com a Comissão |
| N2 | **SMTP para e-mails de login**: qual conta/domínio envia? (Microsoft 365/Google da COMURG ou um serviço como Resend, com DNS do domínio) | Sem isso nenhum candidato recebe o código | Definir antes de 24/09 |
| N3 | **Limite de tamanho por arquivo** (hoje 10 MB no protótipo, no banco e no bucket) | Storage e UX | Manter 10 MB; PDFs escaneados costumam caber |
| N4 | **Edição depois de enviar**: hoje o candidato pode alterar até o encerramento e reenviar; a inscrição continua "submetida" mesmo que ele apague um documento obrigatório | Regra de negócio | Alternativa: voltar a "rascunho" a cada alteração e exigir novo envio |
| N5 | **Retenção e descarte** dos dados e da auditoria (LGPD) | A auditoria hoje é imutável; descarte exigirá procedimento próprio | Definir com o jurídico/DPO |
| N6 | **Nomes oficiais dos Grupos A, B e C** (o protótipo usa descrições derivadas das áreas) | Textos do formulário | Copiar do edital |
| N7 | **Passar para o plano Pro** e quando | Backups, pausa por inatividade, 1 GB de arquivos | Antes de abrir inscrições reais |

## Herdadas do CLAUDE.md (seção 11)

Continuam em aberto; só afetam as fases seguintes (motor de regras, pagamentos, entrevista), exceto onde indicado.

1. Faixas de experiência com limites sobrepostos (Anexo I, item 3) e arredondamento de meses.
2. **Isenção × prazo de pagamento**: decisão da isenção sai em 09/10, inscrições encerram em 07/10 e o item 4.9.5 só aceita comprovante dentro do período. *(Já afeta a Fase 1: hoje o status é `aguardando_isencao`, sem janela extra de pagamento.)*
3. Pedido de isenção por e-mail (texto do edital) versus pela plataforma (implementado assim).
4. Equivalência da pós no Pleno (5 anos substituem a pós, mas o mínimo já é 4).
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
