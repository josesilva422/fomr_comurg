import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { enviarEmail } from "@/lib/email";
import { montarConviteEntrevista, type DadosConviteEntrevista } from "@/lib/convite-entrevista";

// Convite para a entrevista técnica: o banco confere quem chama, se o candidato está convocado (6.5.1) e os campos, e
// grava o convite (auditado); aqui se monta o e-mail padrão e se envia pelo SMTP. O resultado do envio também é gravado.
// Se o SMTP não estiver configurado ou falhar, devolve o texto para a Comissão enviar por outro meio — o convite continua
// visível no portal do candidato.
export async function POST(request: NextRequest) {
  const corpo = await request.json().catch(() => ({}));
  const { inscricao_id, titulo, data, horario, link, orientacoes } = corpo as Record<string, string | undefined>;
  if (!inscricao_id) return NextResponse.json({ erro: "Candidato não informado." }, { status: 400 });

  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) return NextResponse.json({ erro: "Sessão expirada. Entre novamente." }, { status: 401 });

  const { data: convite, error } = await supabase.schema("painel").rpc("registrar_convite_entrevista", {
    p_inscricao_id: inscricao_id,
    p_titulo: titulo ?? "",
    p_data: data || null,
    p_horario: horario || null,
    p_link: link ?? "",
    p_orientacoes: orientacoes ?? null,
  });
  if (error || !convite) {
    const status = error?.code === "42501" ? 403 : 400;
    return NextResponse.json({ erro: error?.message ?? "Não foi possível registrar o convite." }, { status });
  }

  const c = convite as DadosConviteEntrevista & { id: string; email: string };
  const msg = montarConviteEntrevista(c);
  let enviado = false;
  let erroEnvio: string | null = null;
  try {
    enviado = await enviarEmail(c.email, msg);
    if (!enviado) erroEnvio = "SMTP não configurado no servidor";
  } catch (e) {
    erroEnvio = e instanceof Error ? e.message : "falha no envio";
  }
  await supabase.schema("painel").rpc("marcar_convite_enviado", { p_convite_id: c.id, p_enviado: enviado, p_erro: erroEnvio });

  return NextResponse.json({ ok: true, enviado, email: c.email, ...(enviado ? {} : { assunto: msg.assunto, texto: msg.texto }) });
}
