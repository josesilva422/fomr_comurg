// Tipos do resultado do motor de regras (schema `painel`, funções em supabase/migrations/20260922*).
import type { Grupo, Nivel, StatusInscricao } from "./tipos";

export interface AvaliacaoResumo {
  inscricao_id: string;
  nome: string;
  cpf: string;
  email: string;
  telefone: string;
  grupo: Grupo;
  nivel: Nivel;
  status: StatusInscricao;
  habilitado: boolean;
  motivos: { codigo: string; mensagem: string }[];
  pontos_formacao: number;
  pontos_cursos: number;
  pontos_experiencia: number;
  total: number;
  submetida_em: string | null;
  calculado_em: string;
  posicao: number | null;
  vagas: number;
  convocado: boolean;
}

export interface CronogramaItem {
  ordem: number;
  evento: string;
  data_inicio: string | null;
  data_fim: string | null;
  detalhe: string | null;
}

export interface ItemFormacao {
  id: string;
  tipo: string;
  denominacao: string;
  data_conclusao: string;
  pontos: number;
  motivo_rejeicao: string | null;
  observacao: string | null;
}

export interface ItemCurso {
  id: string;
  tipo: string;
  denominacao: string;
  carga_horaria: number | null;
  data_conclusao: string;
  pontos: number;
  motivo_rejeicao: string | null;
  no_catalogo_do_grupo: boolean;
  observacao: string | null;
}

export interface Detalhamento {
  formacao: { itens: ItemFormacao[]; total: number; teto: number };
  cursos: { itens: ItemCurso[]; total: number; teto: number };
  experiencia: { minimo_meses: number; meses_comprovados: number; excedente_meses: number; pontos: number; teto: number };
  avisos_metodologicos: string[];
}

export interface AvaliacaoDetalhada {
  inscricao_id: string;
  habilitado: boolean;
  motivos: { codigo: string; mensagem: string }[];
  pontos_formacao: number;
  pontos_cursos: number;
  pontos_experiencia: number;
  total: number;
  detalhamento: Detalhamento;
  versao_motor: string;
  status: string;
  calculado_em: string;
}

export const fmtMeses = (m: number) => {
  const a = Math.floor(m / 12);
  const r = m % 12;
  const p: string[] = [];
  if (a) p.push(`${a} ${a > 1 ? "anos" : "ano"}`);
  if (r || !a) p.push(`${r} ${r === 1 ? "mês" : "meses"}`);
  return p.join(" e ");
};
