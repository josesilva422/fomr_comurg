import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { enviarConvite } from "@/lib/email-convite";

// Cria o convite (o banco confere se quem chama tem permissão e grava na auditoria) e envia o link por e-mail.
// Se o SMTP não estiver configurado ou falhar, devolve o link só ao convidante, para ele enviar por outro meio.
export async function POST(request: NextRequest) {
  const { email } = await request.json().catch(() => ({}));
  if (!email || typeof email !== "string") return NextResponse.json({ erro: "Informe o e-mail." }, { status: 400 });

  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) return NextResponse.json({ erro: "Sessão expirada. Entre novamente." }, { status: 401 });

  const { data: token, error } = await supabase.schema("painel").rpc("criar_convite", { p_email: email });
  if (error || !token) {
    const status = error?.code === "42501" ? 403 : 400;
    return NextResponse.json({ erro: error?.message ?? "Não foi possível criar o convite." }, { status });
  }

  const link = `${request.nextUrl.origin}/painel/convite?t=${token}`;
  const { data: perfil } = await supabase.schema("painel").rpc("listar_usuarios_painel");
  const eu = (perfil as { user_id: string; nome: string }[] | null)?.find((u) => u.user_id === claims.claims.sub)?.nome ?? "Comissão";

  let enviado = false;
  try {
    enviado = await enviarConvite(email.trim().toLowerCase(), link, eu);
  } catch {
    enviado = false;
  }
  return NextResponse.json({ ok: true, enviado, ...(enviado ? {} : { link }) });
}
