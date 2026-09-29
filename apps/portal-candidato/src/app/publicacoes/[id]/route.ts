import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

// Link permanente de um documento publicado pela Comissão (edital, retificação, resultado...). O banco só entrega o
// caminho de publicação PUBLICADA, e o Storage só assina arquivo publicado (policy publicacoes_publico_le); a URL
// assinada vale 5 minutos, então o link a compartilhar é sempre este (/publicacoes/{id}).
export async function GET(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) return new NextResponse("Documento não encontrado.", { status: 404 });

  const supabase = await createClient();
  const { data } = await supabase.rpc("arquivo_da_publicacao", { p_id: id });
  const arquivo = (data as { arquivo_path: string; arquivo_nome: string | null }[] | null)?.[0];
  if (!arquivo) return new NextResponse("Documento não encontrado ou retirado do ar.", { status: 404 });

  const { data: assinada, error } = await supabase.storage.from("publicacoes").createSignedUrl(arquivo.arquivo_path, 300);
  if (error || !assinada) return new NextResponse("Não foi possível abrir o documento. Tente de novo.", { status: 502 });
  return NextResponse.redirect(assinada.signedUrl, 302);
}
