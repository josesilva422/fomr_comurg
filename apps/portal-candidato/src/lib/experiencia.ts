// Contagem de experiência: unidade = mês, inclusive; períodos simultâneos contam uma só vez (edital 5.4.1 e 5.4.2).
// Aqui a conta é só INFORMATIVA para o candidato; a contagem oficial é feita pela Comissão/motor de regras.
import type { TipoDocumento, TipoVinculo, Vinculo } from "./tipos-inscricao";

/** Vínculo ativo é contado até o encerramento das inscrições (item 3.1). */
export const MES_ENCERRAMENTO = "2026-10-01";

/** 'YYYY-MM-DD' ou 'YYYY-MM' -> índice de mês (ano*12 + mês-1). */
export function indiceMes(data: string | null | undefined): number | null {
  if (!data || !/^\d{4}-\d{2}/.test(data)) return null;
  return Number(data.slice(0, 4)) * 12 + Number(data.slice(5, 7)) - 1;
}

/** 'YYYY-MM' (campo mês) -> 'YYYY-MM-01' (banco). */
export const mesParaData = (mes: string) => `${mes}-01`;

export function intervalo(v: Pick<Vinculo, "inicio" | "fim" | "ativo">): [number, number] | null {
  const s = indiceMes(v.inicio);
  const e = v.ativo ? indiceMes(MES_ENCERRAMENTO) : indiceMes(v.fim);
  return s != null && e != null && e >= s ? [s, e] : null;
}

/** União de intervalos de meses (inclusivos): total de meses sem contar sobreposição duas vezes. */
export function uniaoMeses(intervalos: [number, number][]): number {
  const ordenados = [...intervalos].sort((a, b) => a[0] - b[0]);
  let total = 0;
  let ini: number | null = null;
  let fim = 0;
  for (const [s, e] of ordenados) {
    if (ini === null) {
      ini = s;
      fim = e;
    } else if (s <= fim + 1) {
      fim = Math.max(fim, e);
    } else {
      total += fim - ini + 1;
      ini = s;
      fim = e;
    }
  }
  return ini === null ? total : total + fim - ini + 1;
}

export function formatarMeses(m: number): string {
  const anos = Math.floor(m / 12);
  const meses = m % 12;
  const partes: string[] = [];
  if (anos) partes.push(`${anos} ${anos > 1 ? "anos" : "ano"}`);
  if (meses || !anos) partes.push(`${meses} ${meses === 1 ? "mês" : "meses"}`);
  return partes.join(" e ");
}

/** Vínculos que se sobrepõem a outro (para o selo "simultâneo"). */
export function idsSimultaneos(vinculos: Vinculo[]): Set<string> {
  const com = vinculos
    .map((v) => ({ id: v.id, iv: intervalo(v) }))
    .filter((x): x is { id: string; iv: [number, number] } => x.iv !== null);
  const ids = new Set<string>();
  com.forEach((a, i) => {
    if (com.some((b, j) => i !== j && a.iv[0] <= b.iv[1] && b.iv[0] <= a.iv[1])) ids.add(a.id);
  });
  return ids;
}

/**
 * Comprovante do vínculo (edital 5.3; mesma regra de interno.vinculo_comprovado no banco): devolve o que falta
 * anexar, ou null se o vínculo está comprovado. Só confere a PRESENÇA do documento — a validade é da Comissão.
 */
export function faltaComprovante(tipo: TipoVinculo, anexados: TipoDocumento[]): string | null {
  const tem = (t: TipoDocumento) => anexados.includes(t);
  if (tipo === "privado") {
    return tem("experiencia_ctps") || tem("experiencia_declaracao") || tem("experiencia_contrato")
      ? null
      : "Anexe a CTPS, a declaração do empregador ou o contrato.";
  }
  if (tipo === "publico") {
    return tem("experiencia_publica") || tem("experiencia_contrato")
      ? null
      : "Anexe a certidão ou declaração do órgão, ou o contrato administrativo.";
  }
  const faltam: string[] = [];
  if (!tem("experiencia_autonomo")) faltam.push("o contrato, RPA ou nota fiscal");
  if (!tem("experiencia_declaracao")) faltam.push("a declaração do contratante");
  return faltam.length ? `Anexe ${faltam.join(" e ")}.` : null;
}
