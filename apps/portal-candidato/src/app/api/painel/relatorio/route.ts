import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import { nomeArquivo, type RegistroRelatorio } from "@/lib/relatorio";
import { gerarXlsx } from "@/lib/relatorio-xlsx";
import { gerarPdf } from "@/lib/relatorio-pdf";

export const runtime = "nodejs";

// Só a Comissão baixa (painel.relatorio_respostas confere e ainda grava a geração em interno.auditoria).
// Exige ao menos um filtro: grupo, nível ou nome/CPF.
export async function GET(request: NextRequest) {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) return NextResponse.json({ erro: "Não autenticado." }, { status: 401 });

  const p = request.nextUrl.searchParams;
  const formato = p.get("formato");
  const grupo = p.get("grupo") || null;
  const nivel = p.get("nivel") || null;
  const busca = p.get("busca")?.trim() || null;
  if (formato !== "xlsx" && formato !== "pdf") return NextResponse.json({ erro: "Formato inválido (use xlsx ou pdf)." }, { status: 400 });
  if (!grupo && !nivel && !busca) {
    return NextResponse.json({ erro: "Selecione ao menos um filtro: grupo, nível ou nome/CPF." }, { status: 400 });
  }
  if ((grupo && !(grupo in GRUPOS)) || (nivel && !(nivel in NIVEIS))) return NextResponse.json({ erro: "Filtro inválido." }, { status: 400 });

  const { data, error } = await supabase.schema("painel").rpc("relatorio_respostas", { p_grupo: grupo, p_nivel: nivel, p_busca: busca });
  if (error) {
    const status = error.code === "42501" ? 403 : error.code === "P0001" ? 400 : 500;
    return NextResponse.json({ erro: error.message }, { status });
  }
  const registros = (data ?? []) as RegistroRelatorio[];
  if (!registros.length) return NextResponse.json({ erro: "Nenhuma inscrição enviada encontrada com esses filtros." }, { status: 404 });

  const partes = [grupo ? GRUPOS[grupo as keyof typeof GRUPOS].nome : null, nivel ? NIVEIS[nivel as keyof typeof NIVEIS].nome : null, busca ? `busca "${busca}"` : null];
  const descricao = `Filtro: ${partes.filter(Boolean).join(" · ")} · ${registros.length} candidato(s)`;
  const prefixo = "relatorio-respostas";

  if (formato === "xlsx") {
    const buf = await gerarXlsx(registros);
    return new NextResponse(new Uint8Array(buf), {
      headers: {
        "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "Content-Disposition": `attachment; filename="${nomeArquivo(prefixo, "xlsx")}"`,
        "Cache-Control": "no-store",
      },
    });
  }
  const pdf = await gerarPdf(registros, descricao);
  return new NextResponse(new Uint8Array(pdf), {
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": `attachment; filename="${nomeArquivo(prefixo, "pdf")}"`,
      "Cache-Control": "no-store",
    },
  });
}
