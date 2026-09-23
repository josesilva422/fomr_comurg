# Sistema de Inscrição e Análise Curricular — PSS COMURG 2026

> Arquivo de contexto para o Claude Code. Colocar na raiz do repositório.
> Coloque também o edital original em `docs/Minuta_Edital_PSS_COMURG_2026_v2.docx`: ele é a **fonte de verdade** das regras. Se este arquivo divergir do edital, o edital vence e este arquivo deve ser corrigido.
>
> **Versão do edital considerada:** minuta v2 atualizada em 22/09/2026 08:07 (arquivo "Minuta_Edital_PSS_COMURG_2026_v2 - 22-09-2026-08-07.docx", recebido por WhatsApp e salvo em `docs/`). Mudanças em relação à versão de 21/09/2026 (conferidas por diff completo do texto):
> 1. **Anexo I, item 1 (Formação Acadêmica Adicional):** Especialização/MBA deixou de ter limite de quantidade (antes: até 6,0 pts / máx. 3 títulos) — agora "sem limite de quantidade", respeitando só o teto global de 10,0 pts do critério. Mestrado e doutorado **não mudaram** (máx. 1 título cada). Cursos/Certificações (item 2) e Experiência (item 3) **não mudaram**. Já corrigido no motor de regras (migração `20260922160000_formacao_especializacao_sem_limite.sql`).
> 2. **Item 4.9 (chave Pix):** o texto agora cita a chave `pss2026comurg@comurg.com.br` — o sistema já usava essa chave (`interno.configuracao`), então a divergência antes registrada aqui está resolvida.
> 3. **Item 6.5.1 (convocação para entrevista):** de "até 5 candidatos por vaga" para **"até 3 candidatos por vaga"**. Implementado em 22/09/2026 (migração `20260922170000_convocacao_e_cronograma.sql`) — ver seção 8.6.
> 4. **Anexo IV (cronograma):** entrevistas e etapas seguintes foram antecipadas (entrevistas agora `03/11 a 12/11`, resultado final `até 25/11`, convocações `a partir de 26/11` — era `11/12` e `12/12`). Os 18 itens do Anexo IV estão em `interno.cronograma` (mesma migração), guardados no banco e disponíveis em `painel.listar_cronograma()`; a seção que os mostrava no painel foi **retirada em 23/09/2026** a pedido do responsável.
> 5. **Anexo III (Matriz de Comprovação Documental):** reescrito com uma linha por tipo de documento (antes era mais resumido); não introduz exigência nova além do que já está nas seções 8.1.2 e 8.4 deste arquivo.

---

## 1. Objetivo

Construir a plataforma digital oficial do **Processo Seletivo Simplificado (PSS) da COMURG 2026** (Companhia de Urbanização de Goiânia), para contratação temporária de **Analistas de Governança** (Grupos A, B e C; níveis Júnior, Pleno e Sênior).

A plataforma deve:

1. Receber inscrições (formulário + upload de documentos + comprovante de Pix).
2. Armazenar tudo com segurança no Supabase (Postgres + Storage).
3. Extrair dados dos documentos com IA (pré-análise).
4. Calcular **habilitação** e **pontuação curricular** por um **motor de regras determinístico** (código, nunca IA).
5. Oferecer à Comissão Organizadora uma fila de revisão humana, com justificativa por decisão.
6. Publicar resultados, receber recursos e digitalizar a entrevista técnica (Anexo II).
7. Gerar classificação final por Grupo e Nível, com desempates e cadastro de reserva.

## 2. Princípios inegociáveis

1. **A IA extrai; o código pontua.** Nenhuma nota é calculada por LLM. O LLM só transforma documentos em dados estruturados com evidência.
2. **Decisão humana.** O edital exige decisões fundamentadas e registradas (itens 1.5 e 1.6) e veda eliminação por decisão individual de membro da Comissão. Nenhum resultado é publicado sem aprovação humana registrada. A IA nunca habilita, inabilita ou elimina sozinha.
3. **Explicabilidade.** Toda pontuação guarda o detalhamento: qual critério, qual documento, qual trecho, qual regra e qual versão do motor.
4. **Reprodutibilidade.** Guardar a extração validada, versão do modelo e do prompt, hash SHA-256 dos arquivos e versão do motor de regras. Recalcular a pontuação deve dar o mesmo resultado sempre.
5. **Imutabilidade após o prazo.** Encerradas as inscrições, o servidor bloqueia inclusão ou troca de documentos (itens 5.5.3 e 9.4). O bloqueio é no backend, com horário do servidor, nunca só na interface.
6. **Duas áreas separadas.** Portal do candidato e painel interno são apps distintos; o candidato só vê o que o gestor publica. Ver seção 6.
7. **LGPD desde o início.** O sistema trata laudo com CID (dado de saúde), autodeclaração racial, CPF e documentos pessoais. Ver seção 10.
8. **Nada de segredos no repositório.** Chaves em variáveis de ambiente.

## 3. Cronograma do edital (Anexo IV)

| Evento | Data |
|---|---|
| Publicação do edital | 24/09/2026 |
| Impugnação | 25 e 26/09 |
| Inscrições + pedidos de isenção | 24/09 a 07/10 |
| Resposta às isenções e impugnações | até 09/10 |
| Homologação das inscrições | até 13/10 |
| Habilitação + análise curricular | 14 a 20/10 |
| Resultado preliminar | até 22/10 |
| Recurso | 23, 24 e 27/10 |
| Julgamento dos recursos | 28, 29 e 30/10 |
| Resultado definitivo AC + convocação p/ entrevista | até 31/10 |
| Entrevistas | 03/11 a 12/11 |
| Resultado preliminar das entrevistas | até 14/11 |
| Recurso | 17, 18 e 19/11 |
| Julgamento dos recursos | 20, 21 e 24/11 |
| Resultado final + homologação | até 25/11 |
| Início das convocações | a partir de 26/11 |

> Datas da fase de entrevista/recursos/resultado final antecipadas no edital atualizado em 22/09/2026 (antes: 28/11, 02/12, 05/12, 10/12, 11/12, 12/12, respectivamente). As datas de inscrição (24/09 a 07/10) não mudaram.

**Prioridade de entrega:** o MVP de inscrição (formulário, upload, Pix, trava de prazo) precisa estar no ar em 24/09/2026. O motor de regras e a extração por IA podem ser entregues durante o período de inscrição e devem estar prontos e testados antes de 14/10.

## 4. Stack

- **Banco, Auth, Storage:** Supabase (região São Paulo, `sa-east-1`), plano pago.
- **Frontend:** React + TypeScript (TanStack Start ou Next.js: definir no início e manter). Tailwind.
- **Worker de extração e motor de regras:** Python 3.12, FastAPI, Pydantic v2, pytest.
- **Fila:** Supabase Queues (pgmq) ou tabela `jobs` com polling; o worker processa fora do request.
- **IA de extração:** API da Anthropic com PDF/imagem como entrada e saída estruturada validada por schema Pydantic. O nome do modelo vem de variável de ambiente (`EXTRACTION_MODEL`), sem hardcode.
- **Pix:** o edital fixa uma **chave estática da COMURG** (item 4.9; hoje o e-mail `pss2026comurg@comurg.com.br`) e exige **upload do comprovante** (4.9.3). Portanto não há cobrança dinâmica por candidato: a verificação é feita sobre o comprovante (extração por IA + regras determinísticas) e conferida pelo financeiro contra o extrato bancário, usando o E2E ID como chave.
- **Testes:** pytest (motor), Vitest/Playwright (frontend).

## 5. Estrutura sugerida do repositório

```
/
├── CLAUDE.md
├── docs/
│   ├── Minuta_Edital_PSS_COMURG_2026_v2.docx
│   ├── decisoes-pendentes.md
│   └── lgpd-ripd.md
├── supabase/
│   ├── migrations/
│   ├── seed/            # listas de cursos por grupo/nível, catálogo de cursos pontuáveis
│   └── functions/       # webhooks (ex.: Pix)
├── apps/
│   ├── portal-candidato/  # área pública: inscrição, documentos, Pix, resultados próprios, recurso
│   ├── painel-interno/    # área restrita: Comissão, financeiro, avaliadores, gestor (subdomínio próprio)
│   └── worker/            # FastAPI: extração (IA) + jobs
├── packages/
│   └── motor_regras/    # Python puro, sem I/O, sem IA, 100% testado
└── tests/
    └── fixtures/        # candidatos fictícios (JSON) e PDFs sintéticos
```

## 6. Arquitetura de duas áreas e perfis de acesso

O sistema tem **duas áreas separadas**, com o mesmo projeto Supabase e o mesmo domínio-base:

| Área | Quem usa | Endereço | Acesso |
|---|---|---|---|
| **Portal do candidato** | candidatos | `inscricao.<dominio>` | cadastro público (e-mail/senha ou gov.br) |
| **Painel interno** | Comissão, financeiro, avaliadores, gestor, admin | subdomínio interno separado, sem link no portal, `noindex` | **somente contas criadas por convite do admin**, sem cadastro público, **MFA obrigatório** |

Regras:

- **Segurança não depende de o candidato desconhecer o painel.** O controle é de acesso: o painel só aceita usuários presentes em `usuarios_internos` (com perfil), e as políticas RLS das tabelas do schema `interno` só liberam linhas a esses perfis. Uma conta de candidato jamais lê o schema `interno`, mesmo chamando a API diretamente.
- **Dois schemas:** `publico` (o que o candidato vê e escreve) e `interno` (análises, rascunhos, notas, decisões, auditoria). O portal do candidato não recebe chaves nem endpoints do painel.
- **Etapa de publicação:** o candidato **não** vê dados internos. Quando o gestor aprova e publica um resultado, o sistema copia para `publico.resultados_candidato` somente o que aquele candidato pode ver: pontuação por etapa, posição, situação e motivação (itens 7.3, 13.2 e 13.3 do edital). Nenhum dado de outros candidatos é exposto além do que o edital manda publicar.
- **Recurso:** aberto pelo candidato no portal (Anexo VI); a análise e a decisão ocorrem no painel interno.
- **Segregação de funções (edital 1.3):** quem analisa não aprova sozinho; quem aprova e publica é o gestor/presidente da Comissão.

### Perfis

- `candidato` (portal): vê e altera só a própria inscrição, e só até o encerramento; depois só consulta resultados próprios e abre recursos.
- `analista_comissao`: revisa extrações e propõe habilitação/pontuação curricular. Não publica.
- `financeiro`: vê pagamentos e isenções; não vê análise curricular.
- `avaliador_entrevista`: vê só os candidatos convocados do Grupo/Nível da sua banca e preenche a **própria ficha** (Anexo II). Não vê as notas dos outros avaliadores até enviar a sua.
- `gestor_comissao` / `presidente_comissao`: aprova, consolida a PF, publica resultados e julga recursos.
- `comissao_heteroidentificacao`: só registra o resultado da heteroidentificação.
- `admin`: gerencia usuários internos e configurações; não altera notas.

Todo acesso a documento sensível (laudo PcD, documentos pessoais) gera linha em `auditoria`.

## 7. Modelo de dados (rascunho)

Todas as tabelas com RLS ativado. `created_at`/`updated_at` em todas.

- `candidatos`: id, user_id (auth), nome, cpf (único), email, telefone, data_nascimento.
- `inscricoes`: id, candidato_id, grupo (A|B|C), nivel (junior|pleno|senior), status, cota_pcd, cota_racial, solicitou_isencao, submetida_em. **Único por candidato** (item 4.5).
- `documentos`: id, inscricao_id, tipo (enum), storage_path, sha256, mime, tamanho_bytes, enviado_em. Nunca sobrescrever: nova versão = nova linha.
- `pagamentos`: id, inscricao_id, e2e_id (único), pagador_nome, pagador_cpf_parcial, favorecido, pago_em, valor, status (pendente|confirmado|divergente|isento), documento_comprovante_id, conferido_por, conferido_em.
- `isencoes`: id, inscricao_id, documento_ids, status, decisao_motivada, decidido_por, decidido_em.
- `vinculos_declarados`: id, inscricao_id, tipo (privado|publico|autonomo), empregador_contratante, cargo, inicio (mês/ano), fim (mês/ano ou vínculo ativo), concomitante (bool), descricao. Preenchido pelo candidato no formulário/currículo (Anexo V); é a base da regra de não sobreposição (5.4.3).
- `verificacoes_externas`: id, inscricao_id, documento_id, tipo (emec|diploma_digital_mec|certificadora), resultado, evidencia (URL/print), responsavel, verificado_em.
- `extracoes`: id, documento_id, modelo, versao_prompt, json_extraido, evidencias (página + trecho por campo), confianca, status (pendente|revisada|corrigida), revisado_por.
- `avaliacoes_curriculares`: id, inscricao_id, habilitacao (habilitado|inabilitado|pendente), motivos, pontos_formacao, pontos_cursos, pontos_experiencia, total, detalhamento (jsonb), versao_motor, status (rascunho|aprovada|publicada).
- `decisoes_revisao`: id, avaliacao_id, campo, valor_anterior, valor_novo, justificativa, autor, data.
- `entrevistas` e `fichas_avaliador`: notas por competência, justificativa obrigatória por competência, total do avaliador.
- `usuarios_internos` (schema `interno`): user_id, nome, perfil, ativo, mfa_habilitado, criado_por.
- `resultados_candidato` (schema `publico`): inscricao_id, etapa, pontuacao, posicao, situacao, motivacao, publicado_por, publicado_em. Só recebe linhas via ação de publicação do gestor.
- `recursos`: id, inscricao_id, etapa, item_impugnado, fundamentacao, documento_id (opcional), status, decisao_motivada.
- `auditoria`: append-only (sem UPDATE/DELETE), com ator, ação, entidade, timestamp e IP.

Tipos de documento (enum): `identidade`, `cpf`, `diploma_graduacao`, `diploma_pos`, `diploma_mestrado`, `diploma_doutorado`, `certificado_curso`, `certificacao_profissional`, `experiencia_ctps`, `experiencia_declaracao`, `experiencia_contrato`, `experiencia_publica`, `experiencia_autonomo`, `art_rrt_acervo`, `declaracao_lideranca` (Sênior, 5.3.4), `historico_escolar`, `revalidacao_diploma`, `laudo_pcd`, `autodeclaracao_racial`, `comprovante_pix`, `requerimento_isencao`, `curriculo_anexo_v`, `traducao_juramentada`.

**Storage:** buckets privados; caminho `documentos/{inscricao_id}/{tipo}/{uuid}.{ext}`; MIME restrito a PDF, JPG e PNG; limite de tamanho por bucket; URLs assinadas de curta duração.

## 8. Regras de negócio (extraídas do edital)

### 8.1 Inscrição

- Só por meio eletrônico (4.1). **Um grupo e um nível por candidato** (4.5).
- Taxa de **R$ 100,00** via **Pix** (4.8 e 4.9). Não há restituição, exceto cancelamento total do certame (4.11).
- Isenção: pedido fundamentado com documentação, durante o período de inscrição (4.10 e 4.10.1). Se for **indeferida após o encerramento das inscrições, a inscrição é desconsiderada** (4.10.2). O sistema precisa do status `aguardando_isenção`. Ver decisões pendentes.
- Requisitos avaliados na **data de encerramento das inscrições** (3.1). Cursos e títulos pontuáveis contam se concluídos **até a data de publicação do edital** (Anexo I).
- **Não se exige registro em conselho de classe** (5.2.1).
- Documento em língua estrangeira exige tradução juramentada (5.5.2).
- Não são considerados documentos ilegíveis, genéricos, incompatíveis ou insuficientes para ligar o candidato à atividade (5.5.1).
- Comissão pode pedir originais ou complementos **só para conferir autenticidade**; **vedada a inclusão tardia** de título ou experiência (5.5.3).
- Falsidade documental em qualquer fase: eliminação imediata e comunicação às autoridades (5.5.4 e 14.3). **Decisão exclusivamente humana**; o sistema apenas sinaliza indícios.
- PcD: laudo médico com CID e descrição da deficiência, emitido em até 12 meses antes do encerramento das inscrições (10.5).

### 8.1.1 Pagamento via Pix (4.9 a 4.9.5)

- Chave: **pss2026comurg@comurg.com.br** (e-mail), informada pelo responsável em 21/09/2026. A minuta atualizada em 22/09/2026 já cita essa chave no item 4.9 (a divergência com o CNPJ, registrada aqui até então, está resolvida). A chave fica em `interno.configuracao` (`pix_chave`), não no código.
- O Pix deve ser feito **pelo próprio candidato**, de conta de sua titularidade, com nome completo e CPF. **Pagamento por terceiros não é aceito** (4.9.1).
- O comprovante deve conter: nome completo e CPF do pagador, data e horário, valor e **código E2E** (4.9.2).
- Anexo **obrigatório** ao concluir a inscrição, em PDF, JPG ou PNG legível (4.9.3). Sem comprovante, o backend não conclui a inscrição (exceto quando houver pedido de isenção em análise).
- A Comissão cruza nome e CPF do pagador com os dados da inscrição; **divergência implica cancelamento** sem restituição (4.9.4). Ver decisão pendente sobre o caráter "automático".
- Só valem comprovantes com data/hora **dentro do período de inscrições** (4.9.5). Antes da abertura ou depois do encerramento, o comprovante é inválido.

Verificações determinísticas a implementar sobre os dados extraídos do comprovante:

1. Valor igual a R$ 100,00.
2. Data/hora dentro da janela de inscrições (fuso `America/Sao_Paulo`; o E2E embute data/hora em UTC, o que permite conferência cruzada; confirmar o formato no manual do BCB).
3. Favorecido/chave = a chave Pix oficial configurada (`pix_chave`).
4. Nome do pagador compatível com o do candidato (normalizar acentos, caixa e abreviações; se não bater com certeza, vai para revisão humana).
5. CPF do pagador: comprovantes de Pix **costumam mascarar o CPF** (só alguns dígitos visíveis). Comparar apenas os dígitos visíveis e marcar como "verificação parcial".
6. **E2E único no sistema:** o mesmo comprovante em duas inscrições gera alerta de fraude.
7. Conferência final do **financeiro** contra o extrato bancário da COMURG pelo E2E.

Resultado de qualquer divergência: status `divergente`, fila de revisão humana. **Nunca cancelar inscrição por regra automática sem decisão registrada e motivada** (edital 1.6; cabe recurso, 9.1.b; ver decisão pendente 15).

### 8.1.2 Comprovação de formação (5.1 e 5.2)

- **Diploma de graduação:** requisito de elegibilidade; apresentado **frente e verso**, legível, com nome completo, CPF, curso, **data de colação de grau**, instituição e assinatura do responsável institucional (5.1.1).
- **Diploma digital emitido a partir de 2022:** deve ter QR Code ou código de autenticação válido, verificado pela Comissão no portal de Diplomas Digitais do MEC; **ausência de código válido = inabilitação** (5.1.2).
- **e-MEC:** a Comissão verifica reconhecimento do curso e credenciamento da instituição; sem reconhecimento ativo na data de conclusão, o diploma não vale (5.1.3).
- **Certificado provisório:** só com histórico escolar com registro de colação de grau e carimbo da instituição (5.1.4).
- **Diploma estrangeiro:** revalidado por universidade pública brasileira (Res. CNE/CES nº 1/2021) (5.1.5).
- **Tecnólogo não é aceito em nenhum grupo ou nível** (5.1.6). O sistema precisa extrair o **grau** do diploma (bacharelado, licenciatura ou tecnológico).
- **Pós lato sensu:** certificado de IES credenciada pelo MEC ou curso recomendado pela CAPES, com nome, denominação, **≥360h** e data de conclusão (5.2.1).
- **Mestrado e doutorado:** diploma reconhecido pelo MEC/CAPES, com os requisitos de identificação do 5.1.1 (5.2.2).
- **Certificações internacionais (PMP, PgMP, PRINCE2, IPMA ou similares):** certificado com nome e data de emissão, **número de credencial ativo** e **código de verificação**. Vencidas ou sem código válido não pontuam (5.2.3).
- **Cursos complementares:** certificado com nome, denominação, **carga horária expressa** e data; sem carga horária não é aceito (5.2.4).

**Verificações externas** (e-MEC, portal de Diplomas Digitais do MEC, portais das certificadoras) são **etapas da Comissão**. O sistema extrai código/QR, monta o link e registra o resultado em `verificacoes_externas` (quem, quando, resultado, evidência). A IA não certifica autenticidade.

### 8.2 Requisitos gerais (3.1, cumulativos)

Brasileiro nato/naturalizado ou português com direitos políticos; quite com obrigações eleitorais e militares; 18 anos ou mais; formação mínima reconhecida pelo MEC; experiência mínima do grupo/nível; sem impedimento legal; sem acúmulo indevido de cargos; boa saúde (exame admissional, fase posterior, fora do escopo do sistema).

### 8.3 Requisitos por Grupo e Nível

Cursos de graduação aceitos (**tecnólogo não é aceito em nenhum grupo ou nível**, 5.1.6): ver listas em `supabase/seed/cursos_por_grupo.json`, criadas a partir do edital (itens 3.2 a 3.4).

Resumo das listas:

- **Engenharias aceitas (quando "Engenharias" aparece abaixo):** Aeronáutica, Agrícola, Agronômica, Ambiental, Biomédica, Cartográfica, Civil, da Computação, de Agrimensura, de Alimentos, de Automação e Controle, de Biossistemas, de Controle e Automação, de Energia, de Materiais, de Minas, de Petróleo, de Produção, de Redes de Comunicação, de Telecomunicações, de Transportes, Elétrica, Eletrônica, Florestal, Física, Geológica, Hídrica, Industrial, Mecânica, Mecatrônica, Metalúrgica, Naval, Nuclear, Química, Sanitária, Sanitária e Ambiental.
- **Grupo A, Júnior e Pleno:** Administração, Arquitetura e Urbanismo, Direito + Engenharias.
- **Grupo A, Sênior:** Arquitetura e Urbanismo, Direito, Eng. Ambiental, Eng. Civil, Eng. de Energia, Eng. Hídrica, Eng. Industrial, Eng. Sanitária, Eng. Sanitária e Ambiental.
- **Grupo B (Júnior, Pleno e Sênior):** Administração, Arquitetura e Urbanismo, Ciências Contábeis, Ciências Econômicas, Direito, Sistemas de Informação, Tecnologia da Informação + Engenharias.
- **Grupo C (Júnior, Pleno e Sênior):** Administração, Arquitetura e Urbanismo, Ciências Contábeis, Ciências Econômicas, Direito + Engenharias.

| Grupo / Nível | Pós-graduação lato sensu | Experiência mínima | Áreas / condição |
|---|---|---|---|
| **A Júnior** | não exige | 1 ano | obras e construção civil; fiscalização de obras ou contratos; orçamentos; planejamento ou gestão de projetos; licitações de engenharia (qualquer uma) |
| **A Pleno** | Gestão de Obras, Orçamentação, Infraestrutura Urbana, Gerenciamento de Projetos, Engenharia de Custos, Gestão e Fiscalização de Contratos ou áreas diretamente relacionadas. **Equivalência:** 5 anos de experiência na área | 4 anos, **sendo ao menos 2** em: fiscalização de obras, elaboração/análise de projetos de engenharia, planejamento e controle de projetos, orçamento de obras, gestão de contratos de engenharia, licitações de engenharia ou infraestrutura urbana e resíduos sólidos | |
| **A Sênior** | **obrigatória:** Gestão de Obras, Gerenciamento de Projetos, Engenharia de Custos, Infraestrutura Urbana ou Gestão e Fiscalização de Contratos | 8 anos, **sendo ao menos 3** em liderança técnica ou responsabilidade principal | |
| **B Júnior** | não exige | 1 ano | planejamento, gestão de projetos, governança, PMO ou monitoramento e controle de projetos |
| **B Pleno** | Gestão de Projetos, Governança Corporativa, Administração Pública, Gestão Estratégica, Planejamento e Controle ou PMO. **Equivalências:** certificação PMP, PgMP, PRINCE2 ou IPMA **ativa**, ou 5 anos de experiência | 4 anos | gestão de projetos, governança de projetos, PMO, planejamento e controle de projetos, gestão de riscos (ao menos uma) |
| **B Sênior** | **obrigatória:** Gestão de Projetos, Governança Corporativa, Administração Pública, Gestão Estratégica ou PMO | 8 anos em gestão de projetos e portfólio, **sendo ao menos 3** em liderança técnica ou responsabilidade principal | |
| **C Júnior** | não exige | 1 ano | instrução de processos licitatórios; fases preparatórias; auxílio em ETP, TR ou Edital; histórico de tramitação processual; análise documental para habilitação/propostas |
| **C Pleno** | Direito Administrativo, Licitações e Contratos Administrativos, Gestão Pública, Auditoria e Compliance, Governança no Setor Público ou Contratos e Convênios Públicos. **Equivalência:** 5 anos em licitações públicas e conformidade | 4 anos | planejamento de licitações, elaboração de editais, julgamento de propostas, padronização de fluxos, controle orçamentário, alinhamento de integridade às diretrizes do TCM-GO |
| **C Sênior** | **obrigatória:** Direito Administrativo, Licitações e Contratos Públicos, Governança Pública, Auditoria e Conformidade, Contratos e Convênios Públicos ou Gestão Estratégica no Setor Público | 8 anos em contratações públicas e conformidade processual de projetos de infraestrutura, **sendo ao menos 3** com responsabilidade técnica principal ou liderança nas atividades acima | |

(Nas linhas A Pleno, A Sênior e semelhantes, a coluna "Áreas / condição" pode estar vazia porque a condição já está descrita na coluna de experiência.)

### 8.4 Comprovação de experiência (5.3, 5.4 e Anexo III)

**Setor privado (5.3.1)**, isoladamente ou combinados:
- **CTPS:** páginas de identificação e de registro, com empregador, cargo/função, data de admissão e de demissão ou vínculo ativo. Se a função estiver em branco ou ilegível, exige declaração do empregador.
- **Declaração do empregador:** papel timbrado, **carimbo do CNPJ**, assinatura do representante legal, nome completo e CPF do declarado, cargo/função, **período exato** (início e fim ou vínculo ativo) e **descrição das atividades**. Sem timbrado, carimbo ou assinatura, não é aceita.
- **Contrato de trabalho ou prestação de serviços:** papel timbrado, carimbo do CNPJ, assinatura das partes, objeto/escopo e vigência.

**Setor público (5.3.2):** certidão ou declaração do órgão, em papel timbrado, com assinatura e carimbo institucional, nome e CPF do declarado, cargo/função, período exato e atividades; ou contrato administrativo/instrumento equivalente com os mesmos elementos.

**Autônomo (5.3.3):** contrato, RPA ou nota fiscal **acompanhado de declaração do contratante** (timbrado, carimbo do CNPJ, assinatura, objeto, período e atividades).

**Liderança técnica ou responsabilidade principal, nível Sênior (5.3.4):** exige **declaração específica** do contratante (timbrado, carimbo do CNPJ, assinatura, nome e CPF, cargo, período) com **descrição explícita das responsabilidades de liderança ou coordenação técnica**. Declaração genérica não vale para esse fim. Tipo de documento: `declaracao_lideranca`.

**ART/RRT/acervo (5.3.5):** válidos e ligados à atividade declarada; não valem em andamento sem baixa ou conclusão.

**Não sobreposição de períodos (5.4):**
- Vínculos simultâneos (dois empregos, emprego + autônomo etc.) são computados **uma única vez**; não há somatório (5.4.1).
- **A unidade de contagem é o mês, inclusive.** Exemplo do edital (5.4.2), que deve virar teste automatizado: CLT de 01/2020 a 12/2022 (3 anos) + autônomo de 06/2021 a 06/2023. A sobreposição (06/2021 a 12/2022) conta uma vez; o tempo válido é 01/2020 a 06/2023 = **3 anos e 6 meses**. Na prática: união dos intervalos em meses.
- O candidato **deve declarar no currículo todos os vínculos simultâneos** (5.4.3). Omitir vínculo concomitante para pontuar indevidamente é falsidade (14.3). O sistema compara `vinculos_declarados` com o que foi extraído dos documentos e **sinaliza** omissões; a caracterização de falsidade é decisão humana.

### 8.5 Pontuação da análise curricular (AC, máximo 60) — Anexo I

**Só pontua o que exceder o requisito mínimo. O que foi usado para cumprir requisito não pontua. Nada é contado duas vezes (6.4.3).**

**a) Formação adicional (máx. 10):** só especialização/pós e stricto sensu concluídos até a publicação do edital, relacionados ao Grupo, de IES credenciada pelo MEC (ou curso recomendado pela CAPES), com nome, denominação, **carga horária mínima de 360h** e data de conclusão.

| Título | Pontos | Limite |
|---|---|---|
| Especialização/MBA (≥360h) | 2,0 | sem limite de quantidade (edital atualizado 22/09/2026) |
| Mestrado | 3,0 | até 3,0 (1 título) |
| Doutorado | 4,0 | até 4,0 (1 título) |

Teto do critério: **10,0**. Não pontuam: pós usada como requisito mínimo, disciplinas isoladas, cursos duplicados ou de conteúdo idêntico, palestras/seminários/congressos sem avaliação formal, cursos sem carga horária comprovada.

**b) Cursos e certificações (máx. 15):** concluídos até a publicação do edital, relacionados ao Grupo/Nível, com certificado contendo nome do candidato, denominação, carga horária e data.

| Tipo | Pontos por item | Limite |
|---|---|---|
| Curso 20–39h | 1,0 | até 5,0 |
| Curso 40–79h | 2,0 | até 6,0 |
| Curso ≥80h | 3,0 | até 9,0 |
| Certificação profissional reconhecida e aderente | 5,0 | limitada ao teto global |

Teto global rígido: **15,0**. Catálogo de cursos pontuáveis por grupo (Anexo I, item 2.1): ver `supabase/seed/cursos_pontuaveis.json`. A lista é **exemplificativa**: cursos fora dela podem ser aceitos se o conteúdo programático mostrar correlação direta, **por deliberação motivada da Comissão** (o motor apenas sinaliza; quem decide é humano).

**c) Experiência específica (máx. 35):** incide só sobre o **tempo excedente ao mínimo do nível**.

| Tempo excedente | Pontos |
|---|---|
| até 1 ano | 5,0 |
| de 1 a 3 anos | 15,0 |
| de 3 a 5 anos | 25,0 |
| acima de 5 anos | 35,0 (teto) |

A pontuação é por **degrau**, não proporcional. **Os limites das faixas se sobrepõem no texto** (ver decisões pendentes). Vedações: períodos concomitantes (conta um só), estágios curriculares, bolsas, monitorias, trabalho voluntário, declarações genéricas e o período usado para cumprir o mínimo.

### 8.6 Etapas, classificação e desempate

- **PF = AC + ET** (máx. 100). AC máx. 60; ET máx. 40.
- **Habilitação** é binária (HABILITADO / INABILITADO), sem pontos; falhar em qualquer requisito obrigatório elimina (6.3.3).
- **Convocação para entrevista:** AC ≥ **35 pontos**; até **3 candidatos por vaga** do Grupo/Nível (quantidade de vagas do item 2.1) — reduzido de 5 para 3 no edital atualizado em 22/09/2026 —, **incluindo empatados na última posição**. Abaixo de 35 não é convocado, mesmo que sobrem vagas na fila (6.4.4 e 6.5.1). **Implementado** em `painel.listar_avaliacoes()` (colunas `posicao`/`vagas`/`convocado`, via `RANK()` por Grupo/Nível — inclui empate na última posição) e `interno.vagas`; exibido no painel (coluna "Convocação"). Ainda **não publicado ao candidato** (etapa de publicação, seção 6, continua pendente).
- **Entrevista (ET, máx. 40):** banca de no mínimo 3 avaliadores; cada um dá nota individual com justificativa; a nota final é a **média aritmética**. Eliminado quem tiver **menos de 15 pontos**, faltar ou fraudar (6.5.7).

  | Competência | Máx. |
  |---|---|
  | Domínio técnico | 10 |
  | Análise e resolução de problemas | 10 |
  | Planejamento e priorização | 5 |
  | Comunicação e articulação técnica | 5 |
  | Caso técnico / situação-problema | 5 |
  | Postura profissional e aderência | 5 |

  **Fluxo no sistema:** cada avaliador preenche a **própria ficha** no painel (nota por competência + justificativa obrigatória + declaração). Fichas ficam **cegas entre si** até cada avaliador enviar a sua; depois de enviada, a ficha fica travada (correção só com justificativa e registro em auditoria). Se houver ficha em papel, o gestor pode transcrever e anexar a digitalização assinada. O sistema calcula a média, aplica o corte de 15 pontos e soma PF = AC + ET.

Faixas do Anexo II: nas competências de peso 10, Insuficiente 0–3, Regular 4–6, Bom 7–8, Excelente 9–10. Nas de peso 5, Insuficiente 0–1, Regular 2–3, Bom 4, Excelente 5. A ficha exige justificativa por competência e declaração do avaliador.
- **Classificação** separada por Grupo e Nível, em ordem decrescente de PF.
- **Desempate, na ordem (7.2):** (I) idade ≥ 60 anos, com preferência ao mais velho (Estatuto do Idoso); (II) maior nota na entrevista; (III) maior pontuação em experiência específica; (IV) maior pontuação total na AC; (V) maior tempo de formação (data de conclusão da graduação, a mais antiga); (VI) maior idade.

### 8.7 Vagas e cadastro de reserva (2.1, 10 e 11)

| Nível | Grupo A | Grupo B | Grupo C | Remuneração |
|---|---|---|---|---|
| Júnior | 1 | 1 | 1 | R$ 8.000,00 |
| Pleno | 1 | 2 | 1 | R$ 11.000,00 |
| Sênior | 1 | 1 | 1 | R$ 15.000,00 |

Tabela seedada em `interno.vagas` (grupo, nivel, quantidade, remuneracao) desde 22/09/2026 — é dali que `painel.listar_avaliacoes()` lê a quantidade de vagas para calcular a convocação (item 8.6).

Total de 10 vagas imediatas. **Vagas não migram entre Grupos ou níveis** sem retificação publicada. Reservas de PcD (5%) e de candidatos negros (20%) não geram vaga imediata nesta distribuição; valem como **preferência no cadastro de reserva**, na ordem de classificação (10.1 e 10.2). Heteroidentificação por comissão de no mínimo 5 membros (10.4), fora do escopo inicial; o sistema só registra a autodeclaração e o resultado.

### 8.8 Recursos (Cap. IX)

Cabem contra: indeferimento de isenção, indeferimento de inscrição, resultado preliminar de habilitação/AC, resultado preliminar da entrevista, resultado de reservas de vagas e resultado preliminar final. Prazo de **3 dias úteis** da publicação, **apenas pela plataforma**, individual, objetivo e fundamentado. **Não se admite juntar título ou experiência que deveria ter sido entregue na inscrição** (exceto documento só para esclarecer autenticidade de um já apresentado). Não há recurso de recurso.

## 9. Pipeline de extração e pontuação

```
upload → hash + registro → job na fila → worker extrai (IA)
      → extração estruturada + evidências (página/trecho) + confiança
      → revisão humana da extração (corrige o que estiver errado)
      → motor_regras(inscricao, extrações validadas) → habilitação + pontos + detalhamento
      → revisão da Comissão → aprovação → publicação do resultado preliminar
```

Regras para a extração:

- Saída obrigatoriamente validada por schema Pydantic; se inválida, reprocessar ou marcar `pendente_revisao`.
- Cada campo extraído traz `pagina` e `trecho_origem`. Campo sem evidência não entra no cálculo.
- Confiança baixa ou campo ausente gera alerta, nunca palpite.
- O LLM **não** decide "tem experiência na área" como veredito final: ele propõe uma classificação com justificativa e citação, e a Comissão confirma. Só depois o motor usa o dado.
- Sinalizar (não decidir): documento ilegível, suspeita de adulteração (metadados, fontes inconsistentes), instituição ausente no e-MEC, diploma sem frente/verso, diploma digital sem QR/código, grau tecnológico, certificação sem número de credencial ou código de verificação, declaração sem timbrado, carimbo ou assinatura, declaração de liderança sem descrição explícita, período sem data de fim, vínculos concomitantes não declarados, comprovante de Pix divergente.
- Prompts versionados em `apps/worker/prompts/` com número de versão gravado em cada extração.

Regras do `motor_regras`:

- Python puro, funções puras, sem rede, sem banco, sem IA.
- Entrada: JSON com dados validados; saída: JSON com habilitação, pontos e `detalhamento` (lista de itens contados, itens rejeitados e o motivo de cada um).
- Datas em `date` (sem hora). Períodos: **união de intervalos em meses, inclusivos** (5.4.2) antes de somar; conversão para anos com regra explícita e documentada.
- Cobertura de testes alta, com um teste por regra citada nas seções 8.x; incluir o exemplo do item 5.4.2 e casos de borda (exatamente 1, 3 e 5 anos de excedente; exatamente 360h; exatamente 35 pontos; empate na última posição de convocação).

## 10. Segurança e LGPD

- RLS em todas as tabelas; nenhuma leitura de tabela sensível sem política explícita.
- Buckets privados; URLs assinadas curtas; nada de links públicos.
- Laudo PcD, autodeclaração racial e documentos pessoais: acesso restrito por perfil e sempre auditado.
- Criptografia em trânsito (TLS) e em repouso; backups; política de retenção definida com a área jurídica.
- Envio a APIs externas de IA: enviar **apenas o documento necessário** à extração, sem dados extras. Registrar isso no RIPD e verificar a questão de transferência internacional de dados com o DPO/jurídico antes de rodar com dados reais.
- Publicações de resultado (13.2 e 13.3): pontuação por etapa e classificação, com minimização de dados pessoais (não expor CPF completo).
- Rate limit e proteção contra bots no formulário; sem CAPTCHA proprietário a contornar.
- Logs de auditoria imutáveis.

## 11. Decisões pendentes (NÃO inventar; perguntar ao responsável)

1. **Faixas de experiência com limites sobrepostos** (Anexo I, item 3): definir como intervalos fechados/abertos, por exemplo `>0 e ≤1`, `>1 e ≤3`, `>3 e ≤5`, `>5`. A granularidade em **meses** já está indicada pelo exemplo do item 5.4.2; falta confirmar o corte exato das faixas e o arredondamento de meses para anos.
2. **Isenção × prazo de pagamento:** a decisão da isenção sai até 09/10, mas as inscrições encerram em 07/10. O item 4.9.5 só aceita comprovantes com data dentro do período de inscrições, então quem tiver a isenção indeferida em 09/10 **não tem como pagar validamente** e perde a inscrição (4.10.2). Definir se haverá janela extra de pagamento após o indeferimento. Enquanto isso, modelar o status `aguardando_isenção`.
3. **Isenção por e-mail vs. plataforma:** o edital diz "exclusivamente por e-mail" (4.10). Confirmar se o pedido será feito por upload na plataforma (recomendado) e ajustar o edital.
4. **Equivalência da pós (Pleno):** 5 anos de experiência substituem a pós, mas o mínimo já é de 4 anos. Definir se o mesmo período pode servir aos dois fins e se o excedente pontua.
5. **"Tecnologia da Informação" no Grupo B** aparece como graduação aceita, mas o item 5.1.6 exclui tecnólogo em todos os grupos e níveis (a dúvida sobre o Sênior foi resolvida). Definir se só vale o bacharelado com esse nome.
6. **Cadastro de reserva do nível Pleno:** a tabela do item 2.1 fala em 5 por grupo (45 no total), mas o item 11.1 limita o Pleno a 20 candidatos (Júnior e Sênior a 15). Definir qual vale.
7. **Cláusula sobre uso de sistema assistido por IA** no edital, com decisão final sempre da Comissão.
8. **Tratamento de mestrado/doutorado em áreas afins** e regra para "áreas diretamente relacionadas" quando a pós não está na lista.
9. **Conferência do Pix:** a chave é estática (CNPJ) e o comprovante é obrigatório. Definir quem concilia com o extrato bancário e como o financeiro acessa o extrato (arquivo OFX/CSV ou API do banco). Tratar o **CPF mascarado** nos comprovantes (verificação parcial).
10. **Identidade do candidato:** login por e-mail/senha ou gov.br (reduz fraude)?

11. **Avaliadores cegos à AC?** Definir se a banca da entrevista pode ver a pontuação curricular do candidato ou se a entrevista é cega a ela (o edital não diz).
12. **Ficha de entrevista:** confirmar que cada avaliador lança a própria nota no sistema (recomendado, em linha com 6.5.5) ou se o gestor transcreverá fichas em papel.
13. **Ficha do Anexo II, Parte 2:** o edital marca como "não publicar", mas está dentro da minuta; a ficha mostra caixas de 1 a 10 mesmo para competências de peso 5 e não prevê nota 0. O sistema validará pelo peso de cada competência; ajustar a ficha.

14. **Rigor formal dos documentos:** o edital exige CPF no diploma e, nas declarações, papel timbrado, **carimbo do CNPJ** e assinatura (5.1.1 e 5.3). Diplomas físicos antigos costumam não ter CPF impresso, e muitas empresas emitem declaração com assinatura digital (ICP-Brasil) sem carimbo. Definir se essas situações inabilitam ou se admitem complemento (histórico escolar, assinatura digital válida). O sistema aplicará o que for decidido.
15. **"Cancelamento automático" (4.9.4):** conflita com a exigência de decisão fundamentada e registrada (1.6), com o recurso contra indeferimento de inscrição (9.1.b) e com o direito de revisão de decisões automatizadas (LGPD, art. 20). Recomendação: a divergência gera **sinalização automática** e o cancelamento só ocorre por decisão motivada da Comissão. Ajustar a redação do edital.
16. **Verificações externas (e-MEC e portal de Diplomas Digitais do MEC):** serão manuais pela Comissão (com registro no sistema) ou haverá tentativa de consulta automatizada? Estimar o volume de candidatos, pois a análise ocorre em 14 a 20/10.

Registrar as respostas em `docs/decisoes-pendentes.md` e refletir no motor e nos testes.

## 12. Fases de implementação

**Fase 1 — MVP de inscrição (meta: 24/09/2026)**
- Projeto Supabase, migrações, RLS, buckets privados.
- Portal do candidato: autenticação e formulário (dados pessoais, grupo/nível, documentos por tipo, upload do comprovante Pix (obrigatório, 4.9.3), cadastro estruturado de vínculos de experiência com períodos e concomitância (5.4.3), campos PcD e cota racial, pedido de isenção).
- Validações: CPF, idade mínima, um grupo/nível por candidato, tipos e tamanho de arquivo.
- Trava de encerramento no backend, hash dos arquivos, auditoria.
- Painel interno mínimo: login por convite com MFA, listagem de inscrições e documentos para a Comissão e conferência de Pix/isenção para o financeiro. Schemas `publico` e `interno` com RLS já separados desde esta fase.

**Fase 2 — Pré-análise (meta: antes de 14/10/2026)**
- Worker de extração, fila, schemas, prompts versionados.
- Motor de regras completo com testes.
- Fila de revisão da Comissão, com documento ao lado dos dados extraídos.

**Fase 3 — Resultados e recursos**
- Etapa de publicação (interno → `publico.resultados_candidato`), resultado preliminar visível ao candidato, formulário de recurso no portal (Anexo VI), julgamento no painel, reprocessamento.

**Fase 4 — Entrevista e classificação**
- Fichas digitais do Anexo II preenchidas por cada avaliador (cegas entre si até o envio), média dos avaliadores, PF, desempates, classificação e cadastro de reserva, exportação de relatórios.

## 13. Convenções de trabalho para o Claude Code

- Trabalhar em **passos pequenos**, com commit por passo. Antes de mexer no motor de regras, escrever o teste.
- Antes de implementar qualquer regra, **citar o item do edital** (ex.: "6.4.4") em comentário ou docstring.
- Em dúvida sobre uma regra, **não inventar**: registrar em `docs/decisoes-pendentes.md` e perguntar.
- Nomes de domínio em português (`inscricao`, `habilitacao`, `pontuacao_curricular`); código, infraestrutura e comentários técnicos podem ser em inglês. Manter consistência em cada camada.
- Interface e mensagens ao candidato em **português do Brasil**, com linguagem clara e acessível.
- Nunca commitar dados reais de candidatos. Fixtures apenas sintéticas.
- Toda migração deve ser reversível e revisada quanto a RLS.
- Não usar `localStorage` para dados de inscrição em andamento sem criptografia; preferir rascunho no banco.
- Toda ação da Comissão que altere estado (habilitar, pontuar, aprovar) grava em `auditoria` e exige justificativa.

## 14. Primeiros passos sugeridos ao iniciar

1. Ler o edital em `docs/` e confirmar o entendimento das seções 8 e 11 deste arquivo, apontando qualquer divergência.
2. Criar a estrutura de diretórios da seção 5.
3. Escrever as migrações do modelo de dados da seção 7, com RLS e buckets.
4. Gerar os seeds `cursos_por_grupo.json` e `cursos_pontuaveis.json` a partir do edital, com teste que confira contagem e conteúdo.
5. Implementar `packages/motor_regras` começando por **habilitação** e **experiência excedente** (o ponto mais delicado), com testes de borda.
6. Só então construir o formulário e o fluxo de upload.
