import { createClient as createRawClient } from "@supabase/supabase-js";
import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

// Etapa 1 do login do painel: quem confere a senha é o BANCO (painel.iniciar_login: hash bcrypt, bloqueio após 5 erros).
// Senha correta abre um desafio de 10 minutos; só então disparamos o código por e-mail. Depois de digitar o código, a tela
// chama painel.concluir_login(), que libera a sessão. Sem senha correta antes, a sessão nunca é liberada no banco.
export async function POST(request: NextRequest) {
  const { email, senha } = await request.json();
  if (!email || !senha) return NextResponse.json({ erro: "Informe e-mail e senha." }, { status: 400 });

  // Cliente descartável, sem sessão: só chama a função do banco.
  const verificador = createRawClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: ok, error } = await verificador.schema("painel").rpc("iniciar_login", { p_email: email, p_senha: senha });

  // Mensagem genérica sempre igual, para não revelar se o e-mail existe ou se é da Comissão.
  if (error || !ok) return NextResponse.json({ erro: "E-mail ou senha inválidos." }, { status: 401 });

  // Só agora envia o código — pelo cliente com cookies, para o verifyOtp seguinte já ter onde gravar a sessão.
  const supabase = await createClient();
  const { error: erroOtp } = await supabase.auth.signInWithOtp({ email, options: { shouldCreateUser: false } });
  if (erroOtp) return NextResponse.json({ erro: "Não foi possível enviar o código agora. Tente de novo em instantes." }, { status: 500 });

  return NextResponse.json({ ok: true });
}
