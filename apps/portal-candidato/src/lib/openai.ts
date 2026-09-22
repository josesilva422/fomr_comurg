// Verificação de documentos via OpenAI (Responses API). SERVIDOR APENAS — nunca importar em um
// componente "use client" (a chave ficaria exposta no navegador).
//
// Princípio do projeto (CLAUDE.md): "A IA extrai; o código pontua." Esta função compara, campo a campo,
// o que o candidato DECLAROU no formulário com o que o documento REALMENTE diz — e cita o trecho. Ela
// NUNCA decide habilitação, pontuação ou autenticidade; quem faz isso é o motor de regras e, por fim,
// a Comissão. Se o documento não menciona algo, a resposta é "não mencionado", nunca um "sim" inventado.
//
// Formato da chamada verificado em developers.openai.com (guias "pdf-files" e "structured-outputs") em
// 22/09/2026. Testado pela primeira vez em 22/09/2026 com a chave fornecida pelo responsável.

const RESPONSES_URL = "https://api.openai.com/v1/responses";
const VERSAO_PROMPT = "verificacao-documento-v2-2026-09-22";

export interface CampoDeclarado {
  campo: string;
  valor: string;
}

const SCHEMA_VERIFICACAO = {
  type: "object",
  properties: {
    legivel: { type: "boolean", description: "false se o documento estiver ilegível, cortado ou genérico demais" },
    comparacoes: {
      type: "array",
      description: "Uma entrada para CADA campo declarado recebido, na mesma ordem.",
      items: {
        type: "object",
        properties: {
          campo: { type: "string", description: "Repita exatamente o nome do campo recebido" },
          documento_diz: { type: ["string", "null"], description: "O que o documento realmente afirma sobre esse assunto, com as palavras dele (ou próximas). Null se o documento não toca no assunto." },
          confere: { type: "string", enum: ["sim", "nao", "nao_mencionado"], description: "sim = o documento confirma o valor declarado; nao = o documento diz algo diferente/contraditório; nao_mencionado = o documento não fala sobre isso" },
        },
        required: ["campo", "documento_diz", "confere"],
        additionalProperties: false,
      },
    },
    observacoes_gerais: { type: ["string", "null"], description: "Algo relevante que não coube nas comparações (ex.: rasura, documento sem assinatura, papel não timbrado)." },
    confianca_geral: { type: "number", description: "0 a 1" },
  },
  required: ["legivel", "comparacoes", "observacoes_gerais", "confianca_geral"],
  additionalProperties: false,
} as const;

function montarPrompt(campos: CampoDeclarado[]): string {
  const lista = campos.map((c, i) => `${i + 1}. ${c.campo}: "${c.valor}"`).join("\n");
  return `Você está conferindo um documento anexado a uma inscrição do PSS COMURG 2026. O candidato DECLAROU os
seguintes dados no formulário (não assuma que estão certos — é isso que você vai checar):

${lista}

Para CADA um dos itens acima, na mesma ordem, diga:
- "confere": "sim" se o documento confirma claramente esse dado; "nao" se o documento diz algo diferente ou
  contraditório; "nao_mencionado" se o documento simplesmente não fala sobre esse assunto (mais comum do que
  parece — por exemplo, um diploma pode não usar a palavra "bacharel" mesmo sendo de bacharelado, ou uma
  declaração pode citar o cargo mas não o período).
- "documento_diz": cite o que o documento REALMENTE afirma sobre aquele assunto, com palavras dele. Se o
  documento não menciona nada relacionado, use null — não invente, não deduza, não complete por dedução ou
  bom senso. Só marque "sim" se estiver escrito ou representado de forma inequívoca no documento.
Marque "legivel": false se o documento estiver ilegível, cortado, ou genérico demais para checar qualquer campo
com segurança. Em "observacoes_gerais", aponte algo relevante fora das comparações (falta de assinatura, papel
sem timbre, carimbo ausente, indício de edição), se houver.`;
}

export interface ResultadoVerificacao {
  legivel: boolean;
  comparacoes: { campo: string; documento_diz: string | null; confere: "sim" | "nao" | "nao_mencionado" }[];
  observacoes_gerais: string | null;
  confianca_geral: number;
}

export async function verificarDocumento(args: {
  bytesBase64: string;
  mime: "application/pdf" | "image/jpeg" | "image/png";
  nomeArquivo: string;
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
      input: [{ role: "user", content: [conteudoArquivo, { type: "input_text", text: montarPrompt(args.camposDeclarados) }] }],
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
