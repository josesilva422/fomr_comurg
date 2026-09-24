import nodemailer from "nodemailer";

// Modelo de e-mail do CONVITE para o painel. (O e-mail do código de acesso é enviado pelo Supabase Auth, com o modelo
// configurado lá.) O envio usa o SMTP das variáveis de ambiente SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS e SMTP_FROM;
// se faltar alguma, não envia e devolve `false` para a tela mostrar o link ao convidante.
export function smtpConfigurado(): boolean {
  return Boolean(process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS);
}

const escapar = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

export function montarConvite(link: string, convidadoPor: string) {
  const quem = escapar(convidadoPor);
  const url = escapar(link);
  const assunto = "Convite para o painel do PSS COMURG 2026";
  const texto = [
    "Você foi convidado(a) para acessar o painel da Comissão do Processo Seletivo Simplificado da COMURG 2026.",
    `Convite enviado por: ${convidadoPor}.`,
    "",
    `Para aceitar, abra o link abaixo (vale por 12 horas e só pode ser usado uma vez): ${link}`,
    "",
    "Como funciona: informe este mesmo e-mail, digite o código que chegará por e-mail e preencha seu nome completo, CPF e uma senha.",
    "Se você não esperava este convite, ignore esta mensagem. Ninguém da COMURG pede sua senha por e-mail.",
  ].join("\n");
  const html = `<!doctype html><html lang="pt-BR"><body style="font-family:Arial,Helvetica,sans-serif;color:#1f2937;line-height:1.5;max-width:560px;margin:0 auto;padding:24px">
<h2 style="color:#0f5c2e;margin:0 0 12px">Convite para o painel do PSS COMURG 2026</h2>
<p>Você foi convidado(a) para acessar o painel da Comissão do Processo Seletivo Simplificado da COMURG 2026.</p>
<p style="color:#4b5563;font-size:14px">Convite enviado por: <b>${quem}</b></p>
<p><a href="${url}" style="display:inline-block;background:#0f5c2e;color:#fff;text-decoration:none;padding:12px 20px;border-radius:6px;font-weight:bold">Aceitar convite</a></p>
<p style="font-size:14px">Este link vale por <b>12 horas</b> e só pode ser usado <b>uma vez</b>.</p>
<p style="font-size:14px"><b>Como funciona:</b> informe este mesmo e-mail, digite o código que chegará por e-mail e preencha seu nome completo, CPF e uma senha.</p>
<p style="font-size:12px;color:#6b7280">Se você não esperava este convite, ignore esta mensagem. Ninguém da COMURG pede sua senha por e-mail.</p>
</body></html>`;
  return { assunto, texto, html };
}

export async function enviarConvite(para: string, link: string, convidadoPor: string): Promise<boolean> {
  if (!smtpConfigurado()) return false;
  const porta = Number(process.env.SMTP_PORT ?? 465);
  const transporte = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: porta,
    secure: porta === 465,
    auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
  });
  const { assunto, texto, html } = montarConvite(link, convidadoPor);
  await transporte.sendMail({ from: process.env.SMTP_FROM ?? process.env.SMTP_USER, to: para, subject: assunto, text: texto, html });
  return true;
}
