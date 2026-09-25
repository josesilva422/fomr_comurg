// Entrevista técnica estruturada (edital 6.5 e Anexo II). Os pesos e as faixas abaixo são os do edital.
export const COMPETENCIAS = [
  { chave: "dominio", rotulo: "Domínio técnico", peso: 10 },
  { chave: "analise", rotulo: "Análise e resolução de problemas", peso: 10 },
  { chave: "planejamento", rotulo: "Planejamento e priorização", peso: 5 },
  { chave: "comunicacao", rotulo: "Comunicação e articulação técnica", peso: 5 },
  { chave: "caso", rotulo: "Caso técnico / situação-problema", peso: 5 },
  { chave: "postura", rotulo: "Postura profissional e aderência às atribuições", peso: 5 },
] as const;

export type ChaveCompetencia = (typeof COMPETENCIAS)[number]["chave"];
export const TOTAL_ENTREVISTA = 40;
export const CORTE_ENTREVISTA = 15; // item 6.5.7
export const BANCA_MINIMA = 3; // item 6.5.2 — a média só aparece a partir daqui
export const MAXIMO_FICHAS = 10; // limite de fichas por candidato (decisão do responsável, 25/09/2026)

/** Faixa do Anexo II para a nota: peso 10 → 0–3/4–6/7–8/9–10; peso 5 → 0–1/2–3/4/5. */
export function faixa(nota: number, peso: number): string {
  if (peso === 10) return nota <= 3 ? "Insuficiente" : nota <= 6 ? "Regular" : nota <= 8 ? "Bom" : "Excelente";
  return nota <= 1 ? "Insuficiente" : nota <= 3 ? "Regular" : nota === 4 ? "Bom" : "Excelente";
}

export interface FichaEntrevista {
  id: string;
  inscricao_id: string;
  avaliador_nome: string;
  nota_dominio: number;
  nota_analise: number;
  nota_planejamento: number;
  nota_comunicacao: number;
  nota_caso: number;
  nota_postura: number;
  just_dominio: string;
  just_analise: string;
  just_planejamento: string;
  just_comunicacao: string;
  just_caso: string;
  just_postura: string;
  total: number;
  updated_at: string;
}

/**
 * Visão de UM candidato para o usuário logado (painel.entrevista_do_candidato). Fichas cegas: nunca vem a nota de
 * outro avaliador — só a contagem, os nomes de quem já enviou e, com 3+ fichas, a média.
 */
export interface EntrevistaDoCandidato {
  convocado: boolean;
  ac: number | null;
  n_fichas: number;
  minimo_fichas: number;
  maximo_fichas: number;
  media_liberada: boolean;
  et: number | null;
  pf: number | null;
  abaixo_do_corte: boolean;
  media_por_competencia: Record<ChaveCompetencia, number> | null;
  avaliadores: { nome: string; enviada_em: string }[];
  minha_ficha: FichaEntrevista | null;
}

/** Linha da página "Minhas fichas" (painel.minhas_entrevistas). */
export interface MinhaEntrevista {
  inscricao_id: string;
  nome: string;
  grupo: "A" | "B" | "C";
  nivel: "junior" | "pleno" | "senior";
  n_fichas: number;
  media_liberada: boolean;
  minha_ficha_total: number | null;
  minha_ficha_em: string | null;
}

export interface LinhaClassificacao {
  inscricao_id: string;
  nome: string;
  cpf: string;
  grupo: "A" | "B" | "C";
  nivel: "junior" | "pleno" | "senior";
  ac: number;
  et: number | null;
  pf: number | null;
  n_fichas: number;
  banca_completa: boolean;
  abaixo_do_corte: boolean;
  posicao: number | null;
}

export const fmtNota = (v: number | null | undefined) =>
  v === null || v === undefined ? "—" : Number(v).toLocaleString("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 2 });
