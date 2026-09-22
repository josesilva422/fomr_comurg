# Fase 2 (parcial) · Motor de regras e painel interno mínimo

Construído em 22/09/2026, um dia antes da entrega, a pedido do responsável ("quero que além do formulário
já calcule a pontuação... e faz o demonstrativo de cada pontuação... também precisa incluir a validação do
documento anexado"). Ver decisões D9 a D12 e pendências P5 a P7 em `decisoes-pendentes.md`.

## O que existe agora

- **Motor de regras** (`interno.calcular_avaliacao`, SQL): habilitação (binária) + pontuação da análise
  curricular (Anexo I: formação adicional, cursos/certificações, experiência específica, máx. 60 pontos),
  com `detalhamento` item a item (o que pontuou, o que não pontuou e por quê, citando o item do edital).
  Nunca decide sozinho: grava sempre com `status = 'rascunho'`.
- **Catálogo de cursos pontuáveis** (Anexo I, item 2.1) extraído do edital para os três grupos
  (`supabase/seed/gerar_cursos_pontuaveis.py`, 64 linhas).
- **Painel mínimo** (`/painel` no mesmo app do portal): lista os candidatos com inscrição enviada, pontuação
  e situação de habilitação; cada linha expande para o detalhamento e os documentos enviados.
- **Extração de documentos por IA** (OpenAI, D11): botão "Analisar com IA" por documento, que lê o PDF/imagem
  e devolve os campos encontrados, os trechos de evidência e a confiança — só transcreve, nunca decide se o
  documento é válido. **Ainda não testado** (falta a chave; ver P6).

## O que foi ASSUMIDO por decisão ainda não confirmada pela Comissão (não inventado às cegas — citado no
código e registrado como pendência)

- **Faixas de experiência excedente**: intervalos `(0,12]`, `(12,36]`, `(36,60]`, `(60,∞)` meses (decisão
  pendente nº 1, ainda em aberto).
- **Equivalência da pós no Pleno**: título de especialização OU 5 anos de experiência OU, só no Grupo B,
  certificação PMP/PgMP/PRINCE2/IPMA ativa — qualquer um dos três libera a habilitação (decisão pendente
  nº 4, ainda em aberto).
- **Pós obrigatória do Sênior**: desconta 1 título de especialização da pontuação (o mesmo que cumpre o
  requisito); os demais títulos pontuam normalmente.
- **Correlação com as atribuições do Grupo** (títulos e cursos "diretamente relacionados"): o motor não
  julga isso — pontua e marca "exige confirmação da Comissão" em cada item pontuado.

Cada um desses pontos aparece também em `detalhamento.avisos_metodologicos`, devolvido junto com o cálculo,
para quem for revisar no painel.

## Segurança

- `interno.usuarios_internos` é a lista de quem acessa o painel — **hoje vazia**. Sem ninguém cadastrado,
  ninguém (nem o responsável) consegue ver a pontuação ainda.
- O painel confere `interno.eh_usuario_interno(auth.uid())` em toda função exposta (`painel.*`); quem não
  está na lista recebe "Acesso restrito à Comissão", mesmo estando logado.
- A Comissão passou a ter **leitura** (só SELECT) de `documentos`, `titulos_declarados`, `cursos_declarados`,
  `vinculos_declarados` e dos arquivos no Storage — antes só o próprio candidato lia os próprios dados.
- **Atalho de hoje, não escondido:** o painel roda nas mesmas rotas e no mesmo login (código por e-mail) do
  portal do candidato. O CLAUDE.md pede duas áreas/apps separados com MFA obrigatório para o painel
  (princípio 6) — isso ainda não foi construído. Ver P5.

## Para você habilitar seu acesso ao painel

1. Faça login uma vez em `/entrar`, com o e-mail que vai usar como Comissão.
2. Me avise qual e-mail foi. Eu confirmo o `user_id` gerado e insiro em `interno.usuarios_internos`.
3. Abra `/painel`.

## Para testar a extração por IA

Falta a chave da OpenAI (`OPENAI_API_KEY`, variável de ambiente do servidor, nunca exposta ao navegador).
Quando tiver, me passe aqui que eu coloco em `apps/portal-candidato/.env.local` (arquivo fora do Git). Se
preferir, edite você mesmo esse arquivo, na linha `OPENAI_API_KEY=`.
