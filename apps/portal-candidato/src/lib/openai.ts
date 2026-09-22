// Verificação de documentos via OpenAI (Responses API). SERVIDOR APENAS — nunca importar em um
// componente "use client" (a chave ficaria exposta no navegador).
//
// Princípio do projeto (CLAUDE.md): "A IA extrai; o código pontua." Esta função faz três coisas com o
// documento: (1) identifica que TIPO de documento ele realmente é, e se bate com o que era esperado;
// (2) resume objetivamente o que ele mostra; (3) compara, campo a campo, o que o candidato DECLAROU no
// formulário com o que o documento REALMENTE diz, citando o trecho. Ela NUNCA decide habilitação,
// pontuação ou autenticidade; quem faz isso é o motor de regras e, por fim, a Comissão.
//
// Bug real encontrado em 22/09/2026 (v5): a IA marcou "confere: sim" pro campo CPF citando o valor
// EXATO que o candidato tinha declarado, mas o documento (um "Relatório Completo" qualquer, anexado
// como identidade) não continha CPF nenhum — a IA só repetiu de volta o valor declarado como se tivesse
// encontrado ele no documento. A v6 reforça bastante a instrução contra isso (ver o prompt abaixo).
//
// Formato da chamada verificado em developers.openai.com (guias "pdf-files" e "structured-outputs") em
// 22/09/2026. Testado pela primeira vez em 22/09/2026 com a chave fornecida pelo responsável.

const RESPONSES_URL = "https://api.openai.com/v1/responses";
const VERSAO_PROMPT = "verificacao-documento-v6-2026-09-22";

export interface CampoDeclarado {
  campo: string;
  valor: string;
}

const SCHEMA_VERIFICACAO = {
  type: "object",
  properties: {
    legivel: { type: "boolean", description: "false se o documento estiver ilegível, cortado ou genérico demais" },
    tipo_documento: {
      type: "object",
      description:
        "Checagem PRIORITÁRIA: o arquivo anexado é mesmo o tipo de documento esperado? Baseie-se SÓ nas características estruturais/oficiais do documento (layout, campos que ele tem, termos que usa, órgão emissor, número de registro, foto, timbre etc.) — NUNCA no fato de ele mencionar o nome ou o CPF da pessoa. Um documento qualquer pode citar o nome e o CPF de alguém sem ser o tipo de documento esperado.",
      properties: {
        o_que_e: {
          type: "string",
          description: "Descreva objetivamente o que esse documento realmente é, só pelas características estruturais dele (ex.: 'Certificado de conclusão do curso Excel Avançado, 40 horas, emitido pela Alura em 2019' ou 'Diploma de Doutorado em Engenharia Mecânica pela UFG, colação em março de 2020'). Nunca conclua o tipo só porque o nome ou o CPF da pessoa aparecem no texto.",
        },
        bate_com_esperado: {
          type: "boolean",
          description: "true se esse documento é claramente do tipo esperado (indicado no início do prompt); false se é claramente outro tipo de documento (ex.: pediram diploma de doutorado e o arquivo é um certificado de curso curto, ou pediram identidade e o arquivo é um relatório qualquer que só cita o nome da pessoa).",
        },
        observacao: { type: ["string", "null"], description: "Se bate_com_esperado for false, explique objetivamente a diferença. Null se bater." },
      },
      required: ["o_que_e", "bate_com_esperado", "observacao"],
      additionalProperties: false,
    },
    resumo_documento: {
      type: "string",
      description:
        "Um resumo objetivo, em português, do que o documento mostra (quem, o quê, quando, onde) — não é uma transcrição literal, é uma síntese curta (1 a 3 frases). Ex.: 'José Gabriel Pereira da Silva concluiu o curso de Ciência da Computação na instituição Unip em 2025.' Use SÓ o que está explicitamente escrito no documento — nunca complete, nunca deduza, nunca inclua um dado que não esteja lá, mesmo que pareça óbvio ou provável.",
    },
    comparacoes: {
      type: "array",
      description:
        "Uma entrada para CADA campo declarado recebido, na mesma ordem. ATENÇÃO — erro grave e comum a evitar: NUNCA repita o valor que o candidato declarou como se ele tivesse sido encontrado no documento. Você só pode dizer 'confere: sim' se conseguir apontar o trecho EXATO do documento (em documento_diz) que diz isso — se não achar esse trecho de verdade no texto do arquivo, é 'nao_mencionado', mesmo que o valor declarado pareça certo ou plausível.",
      items: {
        type: "object",
        properties: {
          campo: { type: "string", description: "Repita exatamente o nome do campo recebido" },
          documento_diz: {
            type: ["string", "null"],
            description:
              "Cite o trecho REAL do documento sobre esse assunto, com as palavras dele (ou muito próximas) — precisa ser algo que você efetivamente leu no arquivo, nunca uma cópia do valor declarado. Null se o documento não toca no assunto.",
          },
          pagina: { type: ["integer", "null"], description: "Número da página do documento (a primeira página é 1) onde está o trecho citado em documento_diz. Null se documento_diz for null, se o arquivo for uma imagem única sem páginas, ou se não for possível determinar a página." },
          confere: { type: "string", enum: ["sim", "nao", "nao_mencionado"], description: "sim = você encontrou, de verdade, um trecho no documento que confirma o valor declarado (cite-o em documento_diz); nao = o documento diz algo diferente/contraditório; nao_mencionado = o documento não fala sobre isso, mesmo que o valor declarado seja plausível" },
        },
        required: ["campo", "documento_diz", "pagina", "confere"],
        additionalProperties: false,
      },
    },
    observacoes_gerais: { type: ["string", "null"], description: "Algo relevante que não coube nas comparações (ex.: rasura, documento sem assinatura, papel não timbrado)." },
    indicios_adulteracao: {
      type: "object",
      description: "Só um APONTAMENTO para a Comissão avaliar — a IA nunca decide se houve fraude (decisão sempre humana, item 14.3 do edital).",
      properties: {
        suspeita: { type: "boolean", description: "true se notar algo visualmente inconsistente com o resto do documento" },
        detalhes: { type: ["string", "null"], description: "O que exatamente chamou atenção (ex.: fonte/tamanho de letra diferente nesse campo, alinhamento fora do padrão, cor de texto distinta, rasura, sobreposição, recorte). Null se suspeita for false." },
      },
      required: ["suspeita", "detalhes"],
      additionalProperties: false,
    },
    confianca_geral: { type: "number", description: "0 a 1" },
  },
  required: ["legivel", "tipo_documento", "resumo_documento", "comparacoes", "observacoes_gerais", "indicios_adulteracao", "confianca_geral"],
  additionalProperties: false,
} as const;

function montarPrompt(campos: CampoDeclarado[], tipoEsperado: string): string {
  const lista = campos.map((c, i) => `${i + 1}. ${c.campo}: "${c.valor}"`).join("\n");
  return `Você está conferindo um documento anexado a uma inscrição do PSS COMURG 2026. O candidato anexou este
arquivo especificamente como comprovante de: **${tipoEsperado}**.

REGRA MAIS IMPORTANTE, vale para TUDO abaixo: NUNCA invente, NUNCA alucine, NUNCA complete com dedução ou bom
senso. Relate só o que você realmente vê escrito ou representado no documento. Em especial: NÃO repita de volta
um valor que o candidato declarou como se ele estivesse confirmado no documento — só porque um dado (nome, CPF,
data) parece plausível não significa que ele está de fato escrito no arquivo. Você só pode afirmar que algo está
no documento se puder citar o trecho exato onde isso aparece.

Faça TRÊS coisas com este documento, nesta ordem.

1) TIPO DO DOCUMENTO (campo "tipo_documento") — a checagem mais importante, faça ANTES de tudo: olhe o documento
inteiro e identifique objetivamente o que ele É (em "o_que_e"), baseado só nas características estruturais e
oficiais dele — layout, campos que ele tem, termos que usa, órgão emissor, número de registro, foto, timbre.
Depois responda em "bate_com_esperado": esse documento é realmente um(a) "${tipoEsperado}"? Um documento de um
tipo completamente diferente do esperado — por exemplo, a pessoa declarou um doutorado e anexou um certificado
de curso de 40 horas, ou declarou identidade e anexou um relatório qualquer que só cita o nome dela — deve ser
marcado como "bate_com_esperado": false, mesmo que o restante do documento pareça legítimo. **O fato de o nome
ou o CPF do candidato aparecerem no texto NÃO significa que o documento é do tipo esperado** — muitos documentos
diferentes citam nome e CPF de alguém sem serem, por exemplo, uma identidade. Isso é diferente de "confere: nao"
nas comparações abaixo: aqui o problema é o tipo do documento como um todo, não um campo específico.

2) RESUMO OBJETIVO, em "resumo_documento": escreva 1 a 3 frases, em português, resumindo o que o documento
REALMENTE é e mostra (quem, o quê, quando, onde) — baseado no que você concluiu em "tipo_documento", nunca no
rótulo esperado (se bate_com_esperado for false, o resumo tem que descrever o documento pelo que ele É, não
pelo que deveria ser). Não é uma transcrição literal completa, é uma síntese direta. Exemplos: "José Gabriel
Pereira da Silva concluiu o curso de Ciência da Computação na instituição Unip em 2025." ou, se o documento não
bate com o esperado, "Este arquivo é um currículo, com formação e experiência profissional de Juliana Prado
Martins — não é um documento de identidade." Use só o que está explicitamente no documento; se o documento
estiver ilegível, diga isso no resumo.

3) COMPARAÇÃO CAMPO A CAMPO: o candidato DECLAROU os seguintes dados no formulário (não assuma que estão certos
— é isso que você vai checar contra o documento). Se o documento for de um tipo completamente diferente do
esperado (passo 1), ainda assim tente comparar os campos com o que o documento realmente diz — provavelmente a
maioria vai dar "nao_mencionado", e isso é esperado e correto:

${lista}

Para CADA um dos itens acima, na mesma ordem, diga:
- "confere": "sim" **somente se você localizou, de fato, um trecho no documento que confirma esse dado** — cite
  esse trecho em "documento_diz". "nao" se o documento diz algo diferente ou contraditório. "nao_mencionado" se o
  documento simplesmente não fala sobre esse assunto — isso é muito mais comum do que parece, e é sempre a
  resposta certa quando você não consegue apontar o trecho exato, mesmo que o valor declarado pareça óbvio,
  provável ou já confirmado em outro campo.
- "documento_diz": cite o trecho REAL do documento, com as palavras dele (ou muito próximas). Nunca copie o
  valor declarado aqui sem antes ter certeza de que ele está mesmo escrito no documento. Se o documento não
  menciona nada relacionado, use null.
- "pagina": em qual página do documento está esse trecho (a primeira página é 1). Use null se documento_diz for
  null, se o arquivo não tiver conceito de página (uma única imagem), ou se não der para determinar com certeza.

Marque "legivel": false se o documento estiver ilegível, cortado, ou genérico demais para checar qualquer campo
com segurança. Em "observacoes_gerais", aponte algo relevante fora do resumo e das comparações (falta de
assinatura, papel sem timbre, carimbo ausente), se houver.

Em "indicios_adulteracao", repare se algum campo do documento parece visualmente diferente do resto — fonte ou
tamanho de letra que destoa, alinhamento fora do padrão, cor de texto diferente, região com aspecto de
recorte/colagem, sobreposição ou rasura. Isso NÃO é um veredito de fraude (só a Comissão decide isso, olhando o
documento) — é só um apontamento para ela olhar com mais atenção. Marque "suspeita": true apenas quando notar
algo concreto e descreva em "detalhes"; na dúvida, ou se o documento parecer uniforme, marque false.`;
}

export interface ResultadoVerificacao {
  legivel: boolean;
  tipo_documento: { o_que_e: string; bate_com_esperado: boolean; observacao: string | null };
  resumo_documento: string;
  comparacoes: { campo: string; documento_diz: string | null; pagina: number | null; confere: "sim" | "nao" | "nao_mencionado" }[];
  observacoes_gerais: string | null;
  indicios_adulteracao: { suspeita: boolean; detalhes: string | null };
  confianca_geral: number;
}

export async function verificarDocumento(args: {
  bytesBase64: string;
  mime: "application/pdf" | "image/jpeg" | "image/png";
  nomeArquivo: string;
  /** Rótulo do que esse documento deveria ser (ex.: "Diploma de doutorado", "Certificado de curso"). */
  tipoEsperado: string;
  camposDeclarados: CampoDeclarado[];
}): Promise<{ resultado: ResultadoVerificacao; modelo: string; versaoPrompt: string }> {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("OPENAI_API_KEY não configurada no servidor.");
  const modelo = process.env.OPENAI_EXTRACTION_MODEL || "gpt-4o-mini";

  const conteudoArquivo =
    args.mime === "application/pdf"
      ? { type: "input_file", filename: args.nomeArquivo, file_data: `data:${args.mime};base64,${args.bytesBase64}` }
      : { type: "input_image", image_url: `data:${args.mime};base64,${args.bytesBase64}` };

  const resposta = await fetch(RESPONSES_URL, {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: modelo,
      input: [{ role: "user", content: [conteudoArquivo, { type: "input_text", text: montarPrompt(args.camposDeclarados, args.tipoEsperado) }] }],
      text: { format: { type: "json_schema", name: "verificacao_documento", schema: SCHEMA_VERIFICACAO, strict: true } },
    }),
  });

  if (!resposta.ok) {
    const corpo = await resposta.text();
    throw new Error(`OpenAI respondeu ${resposta.status}: ${corpo.slice(0, 500)}`);
  }
  const dados = await resposta.json();
  const textoSaida = dados.output
    ?.flatMap((o: { content?: { text?: string }[] }) => o.content ?? [])
    .find((c: { text?: string }) => typeof c.text === "string")?.text;
  if (!textoSaida) throw new Error("A OpenAI não devolveu texto estruturado (formato de resposta inesperado).");

  return { resultado: JSON.parse(textoSaida) as ResultadoVerificacao, modelo, versaoPrompt: VERSAO_PROMPT };
}

// ---------------------------------------------------------------------------------------------
// Leitura de currículo (candidato): pré-preenche os campos do formulário, sempre EDITÁVEIS.
// Nada disso grava no banco sozinho — cada item vira um cartão igual aos que a pessoa preencheria
// na mão, e só é salvo quando ela clicar em "Salvar" (ou removido se estiver errado). O objetivo é
// listar TUDO que aparecer no currículo (ex.: se tiver 8 cursos, devolver os 8), não um resumo.
const VERSAO_PROMPT_CURRICULO = "leitura-curriculo-v1-2026-09-22";

const SCHEMA_CURRICULO = {
  type: "object",
  properties: {
    graduacao: {
      type: ["object", "null"],
      description: "A graduação principal (bacharelado/licenciatura), se aparecer. Não inclua pós/mestrado/doutorado aqui.",
      properties: {
        curso: { type: ["string", "null"] },
        instituicao: { type: ["string", "null"] },
        grau: { type: ["string", "null"], enum: ["bacharelado", "licenciatura", "tecnologico", null] },
        data_conclusao: { type: ["string", "null"], description: "AAAA-MM-DD (se só houver o ano, use 01-01)" },
      },
      required: ["curso", "instituicao", "grau", "data_conclusao"],
      additionalProperties: false,
    },
    titulos: {
      type: "array",
      description: "Pós-graduação, MBA, mestrado, doutorado — um item por título encontrado.",
      items: {
        type: "object",
        properties: {
          tipo: { type: "string", enum: ["especializacao", "mestrado", "doutorado"] },
          denominacao: { type: "string" },
          instituicao: { type: "string" },
          carga_horaria: { type: ["number", "null"] },
          data_conclusao: { type: ["string", "null"], description: "AAAA-MM-DD" },
        },
        required: ["tipo", "denominacao", "instituicao", "carga_horaria", "data_conclusao"],
        additionalProperties: false,
      },
    },
    cursos: {
      type: "array",
      description: "Cursos complementares e certificações profissionais — um item por curso/certificação, TODOS os que aparecerem.",
      items: {
        type: "object",
        properties: {
          tipo: { type: "string", enum: ["curso", "certificacao"] },
          denominacao: { type: "string" },
          instituicao: { type: "string" },
          carga_horaria: { type: ["number", "null"] },
          data_conclusao: { type: ["string", "null"], description: "AAAA-MM-DD" },
          numero_credencial: { type: ["string", "null"] },
          codigo_verificacao: { type: ["string", "null"] },
        },
        required: ["tipo", "denominacao", "instituicao", "carga_horaria", "data_conclusao", "numero_credencial", "codigo_verificacao"],
        additionalProperties: false,
      },
    },
    vinculos: {
      type: "array",
      description: "Cada experiência profissional (emprego, contrato, autônomo) — um item por vínculo, TODOS os que aparecerem.",
      items: {
        type: "object",
        properties: {
          tipo: { type: "string", enum: ["privado", "publico", "autonomo"] },
          empregador_contratante: { type: "string" },
          cargo: { type: "string" },
          inicio: { type: ["string", "null"], description: "AAAA-MM" },
          fim: { type: ["string", "null"], description: "AAAA-MM, ou null se for o vínculo atual" },
          ativo: { type: "boolean", description: "true se for o emprego/vínculo atual (sem data de fim)" },
          descricao: { type: "string", description: "Resumo objetivo das atividades, com base no que está escrito" },
        },
        required: ["tipo", "empregador_contratante", "cargo", "inicio", "fim", "ativo", "descricao"],
        additionalProperties: false,
      },
    },
    observacoes: { type: ["string", "null"] },
  },
  required: ["graduacao", "titulos", "cursos", "vinculos", "observacoes"],
  additionalProperties: false,
} as const;

const PROMPT_CURRICULO = `Você está lendo o currículo de um candidato do PSS COMURG 2026 para PRÉ-PREENCHER um
formulário de inscrição. A pessoa vai revisar e editar tudo antes de qualquer coisa ser salva — então é melhor
listar um item a mais (que ela apaga) do que esquecer um item (que ela teria que digitar do zero).

Regras:
- Liste TODOS os cursos, certificações, títulos e vínculos de experiência que aparecerem, não só exemplos.
  Se o currículo tiver 8 cursos, devolva 8 itens em "cursos".
  Se tiver 4 empregos, devolva 4 itens em "vinculos".
- Use as palavras do próprio currículo para denominação, cargo, empregador etc. Não traduza nem resuma o nome
  de cursos ou cargos.
  Datas: converta para o formato pedido (AAAA-MM ou AAAA-MM-DD) da melhor forma possível; se só houver o ano,
  use janeiro. Se não conseguir determinar uma data, use null.
- "ativo": marque true apenas para o vínculo mais recente, se o currículo indicar que é o atual (ex.: "atual",
  "presente", "até o momento", sem data de fim).
- Não invente CPF, endereço ou dados que não seja formação/experiência. Não julgue se o candidato está apto;
  isso não é sua tarefa aqui.

Diferença entre "titulos" e "cursos" (não confunda os dois — são pontuados de formas diferentes):
- Só entra em "titulos": pós-graduação lato sensu (especialização/MBA — só conta como título se tiver pelo
  menos 360 horas; se o currículo mostrar menos horas que isso, ou não informar a carga horária, ainda assim
  classifique como "especializacao" em "titulos", que o sistema decide depois se pontua ou não), mestrado
  ou doutorado — sempre um diploma/certificado de pós-graduação de uma instituição de ensino.
- Vai para "cursos" (tipo "curso"): qualquer curso complementar, workshop, treinamento, curso livre ou de
  extensão, curso de plataforma (ex.: Alura, Coursera, ENAP, FGV Online) — mesmo que o nome do curso contenha
  palavras como "avançado", "profissional" ou pareça importante. Um curso NÃO é um título só por ter nome
  pomposo.
- Vai para "cursos" (tipo "certificacao"): certificações profissionais reconhecidas (PMP, PgMP, PRINCE2, IPMA
  ou similares) — essas têm número de credencial e código de verificação; preencha "numero_credencial" e
  "codigo_verificacao" quando o currículo trouxer esses dados, ou null se não trouxer.
- Na dúvida entre título e curso complementar, prefira "cursos" — é mais seguro classificar para baixo do que
  inflar um curso comum como se fosse pós-graduação.`;

export interface DadosCurriculo {
  graduacao: { curso: string | null; instituicao: string | null; grau: "bacharelado" | "licenciatura" | "tecnologico" | null; data_conclusao: string | null } | null;
  titulos: { tipo: "especializacao" | "mestrado" | "doutorado"; denominacao: string; instituicao: string; carga_horaria: number | null; data_conclusao: string | null }[];
  cursos: { tipo: "curso" | "certificacao"; denominacao: string; instituicao: string; carga_horaria: number | null; data_conclusao: string | null; numero_credencial: string | null; codigo_verificacao: string | null }[];
  vinculos: { tipo: "privado" | "publico" | "autonomo"; empregador_contratante: string; cargo: string; inicio: string | null; fim: string | null; ativo: boolean; descricao: string }[];
  observacoes: string | null;
}

// O currículo entra na análise curricular: só PDF (decisão do responsável em 22/09/2026, mesma regra do
// diploma/certificados — ver tipos-inscricao.ts:exigeSomentePdf), então sempre `input_file`, nunca imagem.
export async function lerCurriculo(args: { bytesBase64: string; mime: "application/pdf"; nomeArquivo: string }): Promise<DadosCurriculo> {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("OPENAI_API_KEY não configurada no servidor.");
  const modelo = process.env.OPENAI_EXTRACTION_MODEL || "gpt-4o-mini";

  const conteudoArquivo = { type: "input_file", filename: args.nomeArquivo, file_data: `data:${args.mime};base64,${args.bytesBase64}` };

  const resposta = await fetch(RESPONSES_URL, {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: modelo,
      input: [{ role: "user", content: [conteudoArquivo, { type: "input_text", text: PROMPT_CURRICULO }] }],
      text: { format: { type: "json_schema", name: "leitura_curriculo", schema: SCHEMA_CURRICULO, strict: true } },
    }),
  });

  if (!resposta.ok) {
    const corpo = await resposta.text();
    throw new Error(`OpenAI respondeu ${resposta.status}: ${corpo.slice(0, 500)}`);
  }
  const dados = await resposta.json();
  const textoSaida = dados.output
    ?.flatMap((o: { content?: { text?: string }[] }) => o.content ?? [])
    .find((c: { text?: string }) => typeof c.text === "string")?.text;
  if (!textoSaida) throw new Error("A OpenAI não devolveu texto estruturado (formato de resposta inesperado).");

  return JSON.parse(textoSaida) as DadosCurriculo;
}

export const VERSAO_PROMPT_CURRICULO_EXPORT = VERSAO_PROMPT_CURRICULO;
