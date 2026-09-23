import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from "pdf-lib";
import { fmtCpf, fmtDataHora, montarSecoes, type RegistroRelatorio } from "./relatorio";
import { TIMBRADO_COMURG_BASE64 } from "./timbrado-comurg";

// PDF: um candidato por página (ou mais, se as respostas forem longas — sempre começando numa página nova).
// Fundo de todas as páginas: papel timbrado da COMURG (logo no canto superior esquerdo + marca d'água).
// No topo, ao lado do logo, em destaque: nome de quem respondeu, CPF e data/hora de conclusão. Depois,
// seção a seção, cada pergunta seguida da resposta. As páginas de continuação repetem nome e CPF.
const A4: [number, number] = [595.28, 841.89];
const MARGEM = 40;
const LARGURA = A4[0] - MARGEM * 2;
const VERDE = rgb(0.059, 0.318, 0.196);
const VERDE_CLARO = rgb(0.9, 0.95, 0.92);
const TOPO_TIMBRADO = 112; // altura ocupada pelo logo no papel timbrado (pt, a partir do topo)
const X_DESTAQUE = 150; // o destaque começa à direita do logo
const CINZA = rgb(0.38, 0.4, 0.42);
const TEXTO = rgb(0.1, 0.11, 0.12);

export async function gerarPdf(registros: RegistroRelatorio[], filtroDescricao: string): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  doc.setTitle("Relatório de respostas — PSS COMURG 2026");
  doc.setCreator("PSS COMURG 2026");
  const normal = await doc.embedFont(StandardFonts.Helvetica);
  const negrito = await doc.embedFont(StandardFonts.HelveticaBold);
  const suportados = new Set(normal.getCharacterSet());
  const [timbrado] = await doc.embedPdf(Buffer.from(TIMBRADO_COMURG_BASE64, "base64"), [0]);

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
    pagina.drawPage(timbrado, { x: 0, y: 0, width: A4[0], height: A4[1] });
    const topo = A4[1];
    const larguraDestaque = A4[0] - MARGEM - X_DESTAQUE;
    if (primeira) {
      // destaque no topo, ao lado do logo: nome, CPF e data/hora da conclusão
      pagina.drawText(limpa("RELATÓRIO DE RESPOSTAS — PSS COMURG 2026"), { x: X_DESTAQUE, y: topo - 40, size: 8, font: negrito, color: CINZA });
      const nome = quebrar(r.nome, negrito, 16, larguraDestaque)[0] ?? "";
      pagina.drawText(nome, { x: X_DESTAQUE, y: topo - 60, size: 16, font: negrito, color: VERDE });
      pagina.drawText(limpa(`CPF: ${fmtCpf(r.cpf)}`), { x: X_DESTAQUE, y: topo - 79, size: 12, font: negrito, color: TEXTO });
      pagina.drawText(limpa(`Conclusão do formulário: ${fmtDataHora(r.submetida_em)}`), { x: X_DESTAQUE, y: topo - 95, size: 12, font: negrito, color: TEXTO });
    } else {
      const nome = quebrar(`${r.nome} (continuação)`, negrito, 12, larguraDestaque)[0] ?? "";
      pagina.drawText(nome, { x: X_DESTAQUE, y: topo - 62, size: 12, font: negrito, color: VERDE });
      pagina.drawText(limpa(`CPF: ${fmtCpf(r.cpf)}`), { x: X_DESTAQUE, y: topo - 80, size: 10, font: negrito, color: TEXTO });
    }
    pagina.drawLine({ start: { x: MARGEM, y: topo - TOPO_TIMBRADO }, end: { x: A4[0] - MARGEM, y: topo - TOPO_TIMBRADO }, thickness: 1.5, color: VERDE });
    y = topo - TOPO_TIMBRADO - 26;
  }

  function garantir(altura: number, r: RegistroRelatorio) {
    if (y - altura < MARGEM + 20) novaPagina(r, false);
  }

  for (const r of registros) {
    novaPagina(r, true); // cada candidato começa numa página nova
    for (const secao of montarSecoes(r)) {
      garantir(48, r);
      pagina.drawRectangle({ x: MARGEM, y: y - 4, width: LARGURA, height: 20, color: VERDE_CLARO, opacity: 0.88 });
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
