import { type EmailOtpType } from "@supabase/supabase-js";
import { type NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

// Alternativa ao código digitado: link do e-mail com token_hash (se o modelo do e-mail usar o link).
export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const tokenHash = searchParams.get("token_hash");
  const type = searchParams.get("type") as EmailOtpType | null;

  const destino = request.nextUrl.clone();
  destino.search = "";

  if (tokenHash && type) {
    const supabase = await createClient();
    const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
    if (!error) {
      destino.pathname = "/inscricao";
      return NextResponse.redirect(destino);
    }
  }
  destino.pathname = "/entrar";
  return NextResponse.redirect(destino);
}
