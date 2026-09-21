import type { Candidato, Inscricao } from "@/lib/tipos";
import type { CursoDeclarado, Documento, Pendencia, Titulo, Vinculo } from "@/lib/tipos-inscricao";

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
}

export const docsDoTipo = (docs: Documento[], tipo: string) => docs.filter((d) => d.tipo === tipo);
