import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from "pdf-lib";
import { fmtCpf, fmtDataHora, montarSecoes, type RegistroRelatorio } from "./relatorio";

// PDF: um candidato por página (ou mais, se as respostas forem longas — sempre começando numa página nova).
// No topo, em destaque: nome de quem respondeu, CPF e data/hora de conclusão. Depois, seção a seção,
// cada pergunta seguida da resposta. As páginas de continuação repetem uma faixa menor com nome e CPF.
const A4: [number, number] = [595.28, 841.89];
const MARGEM = 40;
const LARGURA = A4[0] - MARGEM * 2;
const VERDE = rgb(0.059, 0.318, 0.196);
const VERDE_CLARO = rgb(0.9, 0.95, 0.92);
const CINZA = rgb(0.38, 0.4, 0.42);
const TEXTO = rgb(0.1, 0.11, 0.12);

export async function gerarPdf(registros: RegistroRelatorio[], filtroDescricao: string): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  doc.setTitle("Relatório de respostas — PSS COMURG 2026");
  doc.setCreator("PSS COMURG 2026");
  const normal = await doc.embedFont(StandardFonts.Helvetica);
  const negrito = await doc.embedFont(StandardFonts.HelveticaBold);
  const suportados = new Set(normal.getCharacterSet());

  const limpa = (s: string) =>
    Array.from(s.replace(/[→≥]/g, (c) => (c === "→" ? "->" : ">=")))
      .map((ch) => (suportados.has(ch.codePointAt(0)!) ? ch : "?"))
      .join("");

  function quebrar(txt: string, fonte: PDFFont, tamanho: number, largura: number): string[] {
    const saida: string[] = [];
    for (const paragrafo of limpa(txt).split("\n")) {
      let linha = "";
      for (const palavra of paragrafo.split(/\s+/).filter(Boolean)) {
        let pedaco = palavra;
        // palavra maior que a linha (códigos, e-mails longos): quebra por caractere
        while (fonte.widthOfTextAtSize(pedaco, tamanho) > largura) {
          let corte = pedaco.length;
          while (corte > 1 && fonte.widthOfTextAtSize(pedaco.slice(0, corte), tamanho) > largura) corte--;
          if (linha) {
            saida.push(linha);
            linha = "";
          }
          saida.push(pedaco.slice(0, corte));
          pedaco = pedaco.slice(corte);
        }
        const tentativa = linha ? `${linha} ${pedaco}` : pedaco;
        if (fonte.widthOfTextAtSize(tentativa, tamanho) <= largura) linha = tentativa;
        else {
          saida.push(linha);
          linha = pedaco;
        }
      }
      saida.push(linha);
    }
    return saida;
  }

  let pagina!: PDFPage;
  let y = 0;

  function novaPagina(r: RegistroRelatorio, primeira: boolean) {
    pagina = doc.addPage(A4);
    const topo = A4[1];
    if (primeira) {
      // faixa de destaque: nome, CPF e data/hora da conclusão
      const alt = 96;
      pagina.drawRectangle({ x: 0, y: topo - alt, width: A4[0], height: alt, color: VERDE });
      pagina.drawText(limpa("RELATÓRIO DE RESPOSTAS — PSS COMURG 2026"), {
        x: MARGEM, y: topo - 22, size: 8, font: negrito, color: rgb(0.8, 0.9, 0.84),
      });
      const nome = quebrar(r.nome, negrito, 17, LARGURA)[0] ?? "";
      pagina.drawText(nome, { x: MARGEM, y: topo - 46, size: 17, font: negrito, color: rgb(1, 1, 1) });
      pagina.drawText(limpa(`CPF: ${fmtCpf(r.cpf)}`), { x: MARGEM, y: topo - 68, size: 12, font: negrito, color: rgb(1, 1, 1) });
      pagina.drawText(limpa(`Conclusão do formulário: ${fmtDataHora(r.submetida_em)}`), {
        x: MARGEM, y: topo - 85, size: 12, font: negrito, color: rgb(1, 1, 1),
      });
      y = topo - alt - 22;
    } else {
      pagina.drawRectangle({ x: 0, y: topo - 34, width: A4[0], height: 34, color: VERDE_CLARO });
      pagina.drawText(limpa(`${r.nome} — CPF ${fmtCpf(r.cpf)} (continuação)`), { x: MARGEM, y: topo - 22, size: 10, font: negrito, color: VERDE });
      y = topo - 34 - 20;
    }
  }

  function garantir(altura: number, r: RegistroRelatorio) {
    if (y - altura < MARGEM + 20) novaPagina(r, false);
  }

  for (const r of registros) {
    novaPagina(r, true); // cada candidato começa numa página nova
    for (const secao of montarSecoes(r)) {
      garantir(48, r);
      pagina.drawRectangle({ x: MARGEM, y: y - 4, width: LARGURA, height: 20, color: VERDE_CLARO });
      pagina.drawText(limpa(secao.titulo), { x: MARGEM + 8, y: y + 2, size: 11, font: negrito, color: VERDE });
      y -= 26;
      for (const item of secao.itens) {
        const linhasPergunta = quebrar(item.pergunta, negrito, 9, LARGURA);
        const linhasResposta = quebrar(item.resposta, normal, 10.5, LARGURA);
        garantir(linhasPergunta.length * 12 + Math.min(linhasResposta.length, 3) * 14 + 8, r);
        for (const l of linhasPergunta) {
          pagina.drawText(l, { x: MARGEM, y, size: 9, font: negrito, color: CINZA });
          y -= 12;
        }
        for (const l of linhasResposta) {
          garantir(16, r);
          pagina.drawText(l, { x: MARGEM + 6, y, size: 10.5, font: normal, color: TEXTO });
          y -= 14;
        }
        y -= 6;
      }
      y -= 6;
    }
  }

  const total = doc.getPageCount();
  doc.getPages().forEach((p, i) => {
    p.drawText(limpa(`Página ${i + 1} de ${total}  ·  ${filtroDescricao}  ·  Documento confidencial (LGPD) — uso exclusivo da Comissão`), {
      x: MARGEM, y: 22, size: 7.5, font: normal, color: CINZA,
    });
  });

  return doc.save();
}
