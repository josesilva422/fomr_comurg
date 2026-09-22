// Extração de dados de documentos via OpenAI (Responses API). SERVIDOR APENAS — nunca importar em
// um componente "use client" (a chave ficaria exposta no navegador).
//
// Princípio do projeto (CLAUDE.md): "A IA extrai; o código pontua." Esta função só lê o documento e
// devolve campos + trechos de evidência + confiança. Ela NUNCA decide habilitação, pontuação ou
// autenticidade — quem faz isso é o motor de regras (interno.calcular_avaliacao) e, por fim, a Comissão.
//
// Formato da chamada verificado em developers.openai.com (guias "pdf-files" e "structured-outputs")
// em 22/09/2026, mas ainda NÃO testado de ponta a ponta (falta a chave da OpenAI). Confirme o nome do
// modelo em OPENAI_EXTRACTION_MODEL antes do primeiro uso real.

const RESPONSES_URL = "https://api.openai.com/v1/responses";
const VERSAO_PROMPT = "extracao-documento-v1-2026-09-22";

const SCHEMA_EXTRACAO = {
  type: "object",
  properties: {
    campos: {
      type: "object",
      properties: {
        nome_pessoa: { type: ["string", "null"] },
        cpf: { type: ["string", "null"] },
        cargo_funcao: { type: ["string", "null"] },
        empregador_contratante: { type: ["string", "null"] },
        data_inicio: { type: ["string", "null"], description: "AAAA-MM" },
        data_fim: { type: ["string", "null"], description: "AAAA-MM, ou null se vínculo ativo" },
        instituicao_ensino: { type: ["string", "null"] },
        denominacao_curso: { type: ["string", "null"] },
        carga_horaria_horas: { type: ["number", "null"] },
        data_conclusao: { type: ["string", "null"], description: "AAAA-MM-DD" },
        possui_papel_timbrado: { type: ["boolean", "null"] },
        possui_carimbo_cnpj: { type: ["boolean", "null"] },
        possui_assinatura: { type: ["boolean", "null"] },
      },
      required: [
        "nome_pessoa", "cpf", "cargo_funcao", "empregador_contratante", "data_inicio", "data_fim",
        "instituicao_ensino", "denominacao_curso", "carga_horaria_horas", "data_conclusao",
        "possui_papel_timbrado", "possui_carimbo_cnpj", "possui_assinatura",
      ],
      additionalProperties: false,
    },
    trechos_evidencia: {
      type: "object",
      description: "Para cada campo preenchido em `campos`, o trecho exato do documento que o comprova.",
      additionalProperties: { type: "string" },
    },
    legivel: { type: "boolean" },
    confianca_geral: { type: "number", description: "0 a 1" },
    observacoes: { type: ["string", "null"] },
  },
  required: ["campos", "trechos_evidencia", "legivel", "confianca_geral", "observacoes"],
  additionalProperties: false,
} as const;

const PROMPT = `Você está extraindo dados de um documento anexado a uma inscrição do PSS COMURG 2026 (itens 5.1 a 5.5 do edital).
Preencha apenas os campos que aparecem de fato no documento, com o texto como está escrito. Não invente, não deduza,
não complete. Se um campo não aparecer, deixe null. Para cada campo preenchido, cite em "trechos_evidencia" o trecho
exato (ou bem próximo) de onde você tirou a informação. Não avalie se o documento é válido ou autêntico: apenas
transcreva o que está escrito. Marque "legivel": false se o documento estiver ilegível, cortado ou genérico demais
para extrair qualquer campo com segurança.`;

export interface ResultadoExtracao {
  campos: Record<string, string | number | boolean | null>;
  trechos_evidencia: Record<string, string>;
  legivel: boolean;
  confianca_geral: number;
  observacoes: string | null;
}

export async function extrairDocumento(args: {
  bytesBase64: string;
  mime: "application/pdf" | "image/jpeg" | "image/png";
  nomeArquivo: string;
}): Promise<{ resultado: ResultadoExtracao; modelo: string; versaoPrompt: string }> {
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
      input: [{ role: "user", content: [conteudoArquivo, { type: "input_text", text: PROMPT }] }],
      text: { format: { type: "json_schema", name: "extracao_documento", schema: SCHEMA_EXTRACAO, strict: true } },
    }),
  });

  if (!resposta.ok) {
    const corpo = await resposta.text();
    throw new Error(`OpenAI respondeu ${resposta.status}: ${corpo.slice(0, 500)}`);
  }
  const dados = await resposta.json();
  // Responses API: o texto estruturado vem em output[].content[].text (saída "message").
  const textoSaida = dados.output
    ?.flatMap((o: { content?: { text?: string }[] }) => o.content ?? [])
    .find((c: { text?: string }) => typeof c.text === "string")?.text;
  if (!textoSaida) throw new Error("A OpenAI não devolveu texto estruturado (formato de resposta inesperado).");

  return { resultado: JSON.parse(textoSaida) as ResultadoExtracao, modelo, versaoPrompt: VERSAO_PROMPT };
}
