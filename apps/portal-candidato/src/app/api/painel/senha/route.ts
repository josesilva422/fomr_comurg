import { createClient as createRawClient } from "@supabase/supabase-js";
import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

// Etapa 1 do login do painel: confere e-mail + senha SEM abrir sessão no navegador, e só então
// dispara o código por e-mail (etapa 2, verificada direto pelo cliente via supabase.auth.verifyOtp,
// igual ao login do candidato). Ver docs/decisoes-pendentes.md (D13) sobre o alcance real desta camada.
export async function POST(request: NextRequest) {
  const { email, senha } = await request.json();
  if (!email || !senha) return NextResponse.json({ erro: "Informe e-mail e senha." }, { status: 400 });

  // Cliente descartável: nunca grava cookie nem sessão em lugar nenhum, serve só para checar a senha.
  const verificador = createRawClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!, {
    auth: { persistSession: false, autoRefreshToken: false },
    db: { schema: "publico" },
  });
  const { data, error } = await verificador.auth.signInWithPassword({ email, password: senha });
  await verificador.auth.signOut().catch(() => {});

  // Mensagem genérica sempre igual, para não revelar se o e-mail existe ou se é da Comissão.
  const credenciaisInvalidas = () => NextResponse.json({ erro: "E-mail ou senha inválidos." }, { status: 401 });
  if (error || !data.user) return credenciaisInvalidas();

  const autorizado = await verificador.schema("painel").rpc("eh_membro", { p_user_id: data.user.id });
  if (autorizado.error || !autorizado.data) return credenciaisInvalidas();

  // Só agora envia o código — pelo cliente com cookies, para o verifyOtp seguinte já ter onde gravar a sessão.
  const supabase = await createClient();
  const { error: erroOtp } = await supabase.auth.signInWithOtp({ email, options: { shouldCreateUser: false } });
  if (erroOtp) return NextResponse.json({ erro: "Não foi possível enviar o código agora. Tente de novo em instantes." }, { status: 500 });

  return NextResponse.json({ ok: true });
}
