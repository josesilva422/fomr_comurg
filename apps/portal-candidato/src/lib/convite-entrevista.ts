// Mensagem PADRÃO do convite para a entrevista técnica (itens 6.5.1, 6.5.2, 6.5.6 e 6.5.7; Anexo IV). Função pura: o
// painel usa para a pré-visualização e a rota do servidor usa para o e-mail, então o candidato recebe exatamente o que a
// Comissão viu. As orientações adicionais são texto livre da Comissão (opcional).
import { GRUPOS, NIVEIS } from "./requisitos";
import type { Grupo, Nivel } from "./tipos";

export const TITULO_PADRAO = "Entrevista Técnica Estruturada";

export interface DadosConviteEntrevista {
  nome: string;
  grupo: Grupo;
  nivel: Nivel;
  titulo: string;
  data: string; // AAAA-MM-DD
  horario: string; // HH:MM
  link: string;
  orientacoes?: string | null;
  cota_racial?: boolean;
}

const escapar = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

// "2026-11-03" -> "terça-feira, 03/11/2026" (sem fuso: a data é do calendário, não um instante)
export function dataPorExtenso(iso: string): string {
  const [a, m, d] = iso.split("-").map(Number);
  if (!a || !m || !d) return iso;
  const dia = new Date(Date.UTC(a, m - 1, d)).toLocaleDateString("pt-BR", { weekday: "long", timeZone: "UTC" });
  return `${dia}, ${String(d).padStart(2, "0")}/${String(m).padStart(2, "0")}/${a}`;
}

export function montarConviteEntrevista(c: DadosConviteEntrevista) {
  const vaga = `${GRUPOS[c.grupo].nome} (${GRUPOS[c.grupo].descricao}) · Nível ${NIVEIS[c.nivel].nome}`;
  const quando = `${dataPorExtenso(c.data)}, às ${c.horario} (horário de Brasília)`;
  const orientacoes = c.orientacoes?.trim() || "";
  const assunto = `Convocação: ${c.titulo} — PSS COMURG 2026`;

  const avisos = [
    "A entrevista será conduzida por banca de, no mínimo, 3 avaliadores (item 6.5.2).",
    "A entrevista será registrada em ata e, sempre que tecnicamente viável, gravada em áudio e vídeo (item 6.5.6).",
    "O não comparecimento na data e no horário acima elimina o candidato do processo seletivo (item 6.5.7).",
    ...(c.cota_racial
      ? ["Como você se autodeclarou negro(a), a heteroidentificação será realizada na data da sua entrevista (Anexo IV do edital)."]
      : []),
  ];

  const texto = [
    `Prezado(a) ${c.nome},`,
    "",
    `Você foi convocado(a) para a Entrevista Técnica Estruturada do Processo Seletivo Simplificado da COMURG 2026 (Edital nº 001/2026, item 6.5), na vaga ${vaga}.`,
    "",
    `${c.titulo}`,
    `Data e horário: ${quando}`,
    `Link da reunião: ${c.link}`,
    "",
    "Orientações:",
    ...avisos.map((a) => `- ${a}`),
    ...(orientacoes ? ["", "Orientações da Comissão:", orientacoes] : []),
    "",
    "Esta convocação também está disponível na sua área do candidato no portal de inscrição.",
    "",
    "Atenciosamente,",
    "Comissão Organizadora do PSS COMURG 2026",
    "",
    "Mensagem automática. A COMURG não pede senha nem pagamento por e-mail.",
  ].join("\n");

  const html = `<!doctype html><html lang="pt-BR"><body style="font-family:Arial,Helvetica,sans-serif;color:#1f2937;line-height:1.5;max-width:600px;margin:0 auto;padding:24px">
<h2 style="color:#0f5c2e;margin:0 0 12px">Convocação para a Entrevista Técnica</h2>
<p>Prezado(a) <b>${escapar(c.nome)}</b>,</p>
<p>Você foi convocado(a) para a <b>Entrevista Técnica Estruturada</b> do Processo Seletivo Simplificado da COMURG 2026 (Edital nº 001/2026, item 6.5), na vaga <b>${escapar(vaga)}</b>.</p>
<table role="presentation" style="border-collapse:collapse;width:100%;margin:16px 0;border:1px solid #d1d5db;border-radius:8px">
<tr><td style="padding:10px 14px;background:#f3f4f6;width:150px"><b>Entrevista</b></td><td style="padding:10px 14px">${escapar(c.titulo)}</td></tr>
<tr><td style="padding:10px 14px;background:#f3f4f6"><b>Data e horário</b></td><td style="padding:10px 14px">${escapar(quando)}</td></tr>
<tr><td style="padding:10px 14px;background:#f3f4f6"><b>Link da reunião</b></td><td style="padding:10px 14px;word-break:break-all"><a href="${escapar(c.link)}">${escapar(c.link)}</a></td></tr>
</table>
<p><a href="${escapar(c.link)}" style="display:inline-block;background:#0f5c2e;color:#fff;text-decoration:none;padding:12px 20px;border-radius:6px;font-weight:bold">Entrar na reunião</a></p>
<p style="margin-bottom:4px"><b>Orientações:</b></p>
<ul style="margin-top:0;padding-left:20px">${avisos.map((a) => `<li>${escapar(a)}</li>`).join("")}</ul>
${orientacoes ? `<p style="margin-bottom:4px"><b>Orientações da Comissão:</b></p><p style="margin-top:0;white-space:pre-line">${escapar(orientacoes)}</p>` : ""}
<p>Esta convocação também está disponível na sua área do candidato no portal de inscrição.</p>
<p>Atenciosamente,<br>Comissão Organizadora do PSS COMURG 2026</p>
<p style="font-size:12px;color:#6b7280">Mensagem automática. A COMURG não pede senha nem pagamento por e-mail.</p>
</body></html>`;
  return { assunto, texto, html };
}
