import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { lerCurriculo } from "@/lib/openai";

const LIMITE_BYTES = 10 * 1024 * 1024;

// O currículo (curriculo_anexo_v) entra na análise curricular — só PDF, decisão do responsável em
// 22/09/2026 (mesma regra aplicada a diploma, certificados e comprovantes de experiência; ver
// tipos-inscricao.ts:exigeSomentePdf e a migração 20260922130000_pdf_obrigatorio_analise_curricular.sql).
async function ehPdf(bytes: Uint8Array): Promise<boolean> {
  const inicio = String.fromCharCode(...bytes.slice(0, 8));
  return inicio.includes("%PDF-");
}

async function sha256Hex(buffer: ArrayBuffer): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", buffer);
  return [...new Uint8Array(hash)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

// Candidato envia o currículo (Anexo V): salva como documento normal (curriculo_anexo_v) e, além disso,
// pede à IA uma lista do que encontrou, para pré-preencher os cartões das etapas 3 e 4 — sempre editáveis,
// nada é gravado como título/curso/vínculo até a pessoa clicar em "Salvar" em cada um.
export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) return NextResponse.json({ erro: "Não autenticado." }, { status: 401 });

  const { data: inscricao } = await supabase.from("inscricoes").select("id, status").maybeSingle();
  if (!inscricao) return NextResponse.json({ erro: "Complete o cadastro (etapa 1) antes de enviar o currículo." }, { status: 400 });
  if (inscricao.status !== "rascunho") return NextResponse.json({ erro: "A inscrição já foi enviada; não é mais possível anexar novos documentos." }, { status: 403 });

  const form = await request.formData();
  const arquivo = form.get("arquivo");
  if (!(arquivo instanceof File)) return NextResponse.json({ erro: "Nenhum arquivo recebido." }, { status: 400 });
  if (arquivo.size === 0) return NextResponse.json({ erro: "Arquivo vazio." }, { status: 400 });
  if (arquivo.size > LIMITE_BYTES) return NextResponse.json({ erro: "O arquivo passa do limite de 10 MB." }, { status: 400 });

  const buffer = await arquivo.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  if (!(await ehPdf(bytes))) return NextResponse.json({ erro: "O currículo é usado na análise curricular e só é aceito em PDF." }, { status: 400 });
  const mime = "application/pdf" as const;

  const sha256 = await sha256Hex(buffer);
  const caminho = `${inscricao.id}/curriculo_anexo_v/${crypto.randomUUID()}.pdf`;

  // Cada envio de currículo vira um documento novo (histórico nunca é apagado), mas só o mais recente
  // interessa pra Comissão revisar — os anteriores ficam marcados como inativos (mesmo soft-delete usado
  // quando o candidato remove um documento manualmente), sem sumir do banco.
  await supabase.from("documentos").update({ ativo: false }).eq("inscricao_id", inscricao.id).eq("tipo", "curriculo_anexo_v").eq("ativo", true);

  const { error: erroUpload } = await supabase.storage.from("documentos").upload(caminho, bytes, { contentType: mime, upsert: false });
  if (erroUpload) return NextResponse.json({ erro: `Não foi possível salvar o arquivo: ${erroUpload.message}` }, { status: 500 });

  const { error: erroDoc } = await supabase.from("documentos").insert({
    inscricao_id: inscricao.id,
    tipo: "curriculo_anexo_v",
    storage_path: caminho,
    nome_original: arquivo.name.slice(0, 255),
    sha256,
    mime,
    tamanho_bytes: arquivo.size,
  });
  if (erroDoc) return NextResponse.json({ erro: `Arquivo salvo, mas não foi possível registrar: ${erroDoc.message}` }, { status: 500 });

  try {
    const bytesBase64 = Buffer.from(bytes).toString("base64");
    const dados = await lerCurriculo({ bytesBase64, mime, nomeArquivo: arquivo.name });
    return NextResponse.json({ dados });
  } catch (e) {
    // O arquivo já foi salvo (o candidato não perde o upload); só a leitura automática falhou.
    return NextResponse.json({ erro: e instanceof Error ? e.message : "Não foi possível ler o currículo automaticamente. O arquivo foi salvo; preencha os campos manualmente." }, { status: 502 });
  }
}
