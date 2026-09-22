import type { Candidato, Inscricao } from "@/lib/tipos";
import type { CursoDeclarado, Documento, Pendencia, TipoCurso, TipoTitulo, TipoVinculo, Titulo, Vinculo } from "@/lib/tipos-inscricao";

/** Rascunho pré-preenchido pela leitura do currículo — nada disso existe no banco ainda.
 *  A etapa correspondente usa isso só para preencher os campos de um cartão NOVO; a pessoa ainda
 *  precisa clicar em "Salvar" (ou remover) para qualquer coisa virar dado de verdade. */
export interface RascunhoTitulo {
  tipo: TipoTitulo | "";
  denominacao: string;
  instituicao: string;
  carga_horaria: string;
  data_conclusao: string;
}
export interface RascunhoCurso {
  tipo: TipoCurso | "";
  denominacao: string;
  instituicao: string;
  carga_horaria: string;
  data_conclusao: string;
  numero_credencial: string;
  codigo_verificacao: string;
}
export interface RascunhoVinculo {
  tipo: TipoVinculo | "";
  empregador_contratante: string;
  cargo: string;
  inicio: string;
  fim: string;
  ativo: boolean;
  descricao: string;
}
export interface RascunhoGraduacao {
  curso: string;
  instituicao: string;
  grau: "bacharelado" | "licenciatura" | "tecnologico" | "";
  data_colacao: string;
}
export interface RascunhosCV {
  graduacao: RascunhoGraduacao | null;
  titulos: RascunhoTitulo[];
  cursos: RascunhoCurso[];
  vinculos: RascunhoVinculo[];
}

/** Estado da inscrição compartilhado entre as etapas do assistente. */
export interface Contexto {
  userId: string;
  email: string;
  candidato: Candidato | null;
  inscricao: Inscricao | null;
  documentos: Documento[];
  titulos: Titulo[];
  cursos: CursoDeclarado[];
  vinculos: Vinculo[];
  pendencias: Pendencia[];
  /** Busca tudo de novo no banco e devolve as pendências atualizadas. */
  recarregar: () => Promise<Pendencia[]>;
  irPara: (n: number) => void;
  /** Preenchido pela leitura do currículo (etapa 3), consumido uma vez pela etapa 4 (vínculos). */
  rascunhosVinculosCV: RascunhoVinculo[];
  definirRascunhosVinculosCV: (v: RascunhoVinculo[]) => void;
}

export const docsDoTipo = (docs: Documento[], tipo: string) => docs.filter((d) => d.tipo === tipo);
