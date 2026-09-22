// Camada única de armazenamento de documentos.
// Hoje grava no Supabase Storage (bucket privado `documentos`). Para trocar de destino (ex.: um bucket S3
// da COMURG), basta reimplementar `enviarArquivo`: o restante do app não muda.
import type { createClient } from "./supabase/client";
import { exigeSomentePdf, type TipoDocumento } from "./tipos-inscricao";
import { traduzirErro } from "./validacao";

export const LIMITE_BYTES = 10 * 1024 * 1024; // mesmo limite do banco e do bucket
const EXTENSOES = ["pdf", "jpg", "jpeg", "png"];
const EXTENSOES_PDF = ["pdf"];

export interface ReferenciaDocumento {
  titulo_id?: string;
  curso_id?: string;
  vinculo_id?: string;
}

type Cliente = ReturnType<typeof createClient>;

const extensao = (nome: string) => /\.([a-z0-9]+)$/i.exec(nome)?.[1].toLowerCase() ?? "";

/** Confere o CONTEÚDO do arquivo (não só a extensão): PDF, JPEG ou PNG. */
async function detectarMime(f: File): Promise<"application/pdf" | "image/jpeg" | "image/png" | null> {
  const b = new Uint8Array(await f.slice(0, 1024).arrayBuffer());
  const inicio = String.fromCharCode(...b);
  if (inicio.includes("%PDF-")) return "application/pdf";
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (
    b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47 &&
    b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a && b[7] === 0x0a
  )
    return "image/png";
  return null;
}

async function sha256Hex(f: File): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", await f.arrayBuffer());
  return [...new Uint8Array(hash)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

export function tamanhoLegivel(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1048576) return `${Math.round(n / 1024)} KB`;
  return `${(n / 1048576).toFixed(1)} MB`;
}

/** Envia o arquivo e registra em publico.documentos. Devolve uma mensagem de erro, ou null se deu certo. */
export async function enviarArquivo(
  supabase: Cliente,
  inscricaoId: string,
  tipo: TipoDocumento,
  arquivo: File,
  referencia: ReferenciaDocumento = {},
): Promise<string | null> {
  const somentePdf = exigeSomentePdf(tipo);
  const nome = `“${arquivo.name}”`;
  if (arquivo.size === 0) return `${nome}: arquivo vazio.`;
  if (arquivo.size > LIMITE_BYTES) return `${nome}: o arquivo passa do limite de 10 MB. Reduza o tamanho e envie de novo.`;
  if (!(somentePdf ? EXTENSOES_PDF : EXTENSOES).includes(extensao(arquivo.name)))
    return somentePdf ? `${nome}: este documento é usado na análise curricular e só é aceito em PDF.` : `${nome}: formato não aceito. Envie PDF, JPG ou PNG.`;
  const mime = await detectarMime(arquivo);
  if (!mime) return `${nome}: o conteúdo não parece ser um PDF, JPG ou PNG válido.`;
  if (somentePdf && mime !== "application/pdf") return `${nome}: este documento é usado na análise curricular e só é aceito em PDF.`;

  const sha256 = await sha256Hex(arquivo);
  const ext = mime === "application/pdf" ? "pdf" : mime === "image/png" ? "png" : "jpg";
  const caminho = `${inscricaoId}/${tipo}/${crypto.randomUUID()}.${ext}`;

  const { error: erroEnvio } = await supabase.storage
    .from("documentos")
    .upload(caminho, arquivo, { contentType: mime, upsert: false });
  if (erroEnvio) {
    return /row-level security|not allowed|unauthorized/i.test(erroEnvio.message)
      ? "Não foi possível enviar: a inscrição pode já ter sido enviada ou o período encerrou."
      : `${nome}: não foi possível enviar. Verifique a conexão e tente de novo.`;
  }
  const { error: erroRegistro } = await supabase.from("documentos").insert({
    inscricao_id: inscricaoId,
    tipo,
    ...referencia,
    storage_path: caminho,
    nome_original: arquivo.name.slice(0, 255),
    sha256,
    mime,
    tamanho_bytes: arquivo.size,
  });
  return erroRegistro ? traduzirErro(erroRegistro) : null;
}

/** "Remover" = marcar como inativo (o arquivo nunca é apagado; nova versão = novo arquivo). */
export async function removerDocumento(supabase: Cliente, documentoId: string): Promise<string | null> {
  const { error } = await supabase.from("documentos").update({ ativo: false }).eq("id", documentoId);
  return error ? traduzirErro(error) : null;
}
