import ExcelJS from "exceljs";
import { montarSecoes, type RegistroRelatorio } from "./relatorio";

// Excel: uma linha por candidato; a linha 1 traz as PERGUNTAS (uma por coluna) e as linhas de baixo as RESPOSTAS.
export async function gerarXlsx(registros: RegistroRelatorio[]): Promise<Buffer> {
  const wb = new ExcelJS.Workbook();
  wb.creator = "PSS COMURG 2026";
  wb.created = new Date();
  const ws = wb.addWorksheet("Respostas", { views: [{ state: "frozen", xSplit: 2, ySplit: 1 }] });

  const perguntas = montarSecoes(registros[0]).flatMap((s) => s.itens.map((i) => i.pergunta));
  ws.columns = perguntas.map((p) => ({ header: p, key: p, width: Math.min(Math.max(p.length + 4, 18), 48) }));

  for (const r of registros) {
    const respostas = montarSecoes(r).flatMap((s) => s.itens.map((i) => i.resposta));
    const linha = ws.addRow(respostas);
    linha.alignment = { vertical: "top", wrapText: true };
  }

  const cab = ws.getRow(1);
  cab.font = { bold: true, color: { argb: "FFFFFFFF" } };
  cab.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF0F5132" } };
  cab.alignment = { vertical: "middle", wrapText: true };
  cab.height = 42;
  ws.autoFilter = { from: { row: 1, column: 1 }, to: { row: 1, column: perguntas.length } };

  return Buffer.from(await wb.xlsx.writeBuffer());
}
