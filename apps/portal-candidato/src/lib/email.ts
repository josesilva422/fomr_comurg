import nodemailer from "nodemailer";

// Envio de e-mail pelo SMTP das variáveis de ambiente SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS e SMTP_FROM (servidor
// apenas). Se faltar alguma, não envia e devolve `false`, para a tela oferecer o texto ao usuário do painel.
export function smtpConfigurado(): boolean {
  return Boolean(process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS);
}

export const escaparHtml = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

export async function enviarEmail(para: string, msg: { assunto: string; texto: string; html: string }): Promise<boolean> {
  if (!smtpConfigurado()) return false;
  const porta = Number(process.env.SMTP_PORT ?? 465);
  const transporte = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: porta,
    secure: porta === 465,
    auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
  });
  await transporte.sendMail({ from: process.env.SMTP_FROM ?? process.env.SMTP_USER, to: para, subject: msg.assunto, text: msg.texto, html: msg.html });
  return true;
}
