import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { verificarDocumento, type CampoDeclarado } from "@/lib/openai";

// Só a Comissão pode disparar isto (mesma checagem do painel.*). O resultado é sempre um RASCUNHO de
// leitura, nunca uma decisão — a Comissão confirma ou corrige (CLAUDE.md, seção 9).
export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) return NextResponse.json({ erro: "Não autenticado." }, { status: 401 });

  const { data: souComissao } = await supabase.schema("painel").rpc("sou_da_comissao");
  if (!souComissao) return NextResponse.json({ erro: "Acesso restrito à Comissão." }, { status: 403 });

  const { documentoId } = await request.json();
  if (!documentoId) return NextResponse.json({ erro: "documentoId é obrigatório." }, { status: 400 });

  const { data: doc, error: erroDoc } = await supabase
    .from("documentos")
    .select("storage_path, nome_original, mime")
    .eq("id", documentoId)
    .single();
  if (erroDoc || !doc) return NextResponse.json({ erro: "Documento não encontrado ou sem permissão." }, { status: 404 });

  const { data: campos, error: erroCampos } = await supabase.schema("painel").rpc("dados_declarados_documento", { p_documento_id: documentoId });
  if (erroCampos) return NextResponse.json({ erro: erroCampos.message }, { status: 500 });

  const { data: arquivo, error: erroArquivo } = await supabase.storage.from("documentos").download(doc.storage_path);
  if (erroArquivo || !arquivo) return NextResponse.json({ erro: `Não foi possível baixar o arquivo: ${erroArquivo?.message}` }, { status: 500 });

  const bytesBase64 = Buffer.from(await arquivo.arrayBuffer()).toString("base64");

  try {
    const { resultado, modelo, versaoPrompt } = await verificarDocumento({
      bytesBase64,
      mime: doc.mime as "application/pdf" | "image/jpeg" | "image/png",
      nomeArquivo: doc.nome_original,
      camposDeclarados: (campos as CampoDeclarado[] | null) ?? [],
    });

    const { data: registrado, error: erroRegistro } = await supabase.schema("painel").rpc("registrar_extracao", {
      p_documento_id: documentoId,
      p_modelo: modelo,
      p_versao_prompt: versaoPrompt,
      p_json_extraido: resultado,
      p_evidencias: {},
      p_confianca: resultado.confianca_geral,
    });
    if (erroRegistro) return NextResponse.json({ erro: erroRegistro.message }, { status: 500 });

    return NextResponse.json({ extracao: registrado });
  } catch (e) {
    return NextResponse.json({ erro: e instanceof Error ? e.message : "Falha desconhecida na verificação." }, { status: 502 });
  }
}
