// Tipos das tabelas de formação, experiência e documentos (schema `publico`).

export type TipoDocumento =
  | "identidade"
  | "cpf"
  | "diploma_graduacao"
  | "diploma_pos"
  | "diploma_mestrado"
  | "diploma_doutorado"
  | "certificado_curso"
  | "certificacao_profissional"
  | "experiencia_ctps"
  | "experiencia_declaracao"
  | "experiencia_contrato"
  | "experiencia_publica"
  | "experiencia_autonomo"
  | "art_rrt_acervo"
  | "declaracao_lideranca"
  | "historico_escolar"
  | "revalidacao_diploma"
  | "traducao_juramentada"
  | "laudo_pcd"
  | "autodeclaracao_racial"
  | "comprovante_pix"
  | "requerimento_isencao"
  | "curriculo_anexo_v";

export const ROTULO_DOCUMENTO: Record<TipoDocumento, string> = {
  identidade: "Documento de identidade",
  cpf: "Comprovante de CPF",
  diploma_graduacao: "Diploma de graduação",
  diploma_pos: "Certificado de pós-graduação",
  diploma_mestrado: "Diploma de mestrado",
  diploma_doutorado: "Diploma de doutorado",
  certificado_curso: "Certificado de curso",
  certificacao_profissional: "Certificação profissional",
  experiencia_ctps: "CTPS (páginas de identificação e de registro)",
  experiencia_declaracao: "Declaração do empregador ou contratante",
  experiencia_contrato: "Contrato de trabalho ou de prestação de serviços",
  experiencia_publica: "Certidão ou declaração do órgão público",
  experiencia_autonomo: "Contrato, RPA ou nota fiscal",
  art_rrt_acervo: "ART, RRT ou acervo técnico",
  declaracao_lideranca: "Declaração específica de liderança técnica",
  historico_escolar: "Histórico escolar com registro de colação de grau",
  revalidacao_diploma: "Revalidação do diploma",
  traducao_juramentada: "Tradução juramentada",
  laudo_pcd: "Laudo médico",
  autodeclaracao_racial: "Autodeclaração racial",
  comprovante_pix: "Comprovante de pagamento (Pix)",
  requerimento_isencao: "Requerimento de isenção",
  curriculo_anexo_v: "Currículo (Anexo V)",
};

/**
 * Documentos que entram na análise curricular (habilitação + pontuação do Anexo I) só podem ser PDF —
 * decisão do responsável em 22/09/2026. Os demais (identidade, CPF, laudo PcD, autodeclaração racial,
 * comprovante de Pix, requerimento de isenção) continuam aceitando PDF, JPG ou PNG. Mesma lista aplicada
 * no banco (migração `20260922130000_pdf_obrigatorio_analise_curricular.sql`) — mudar aqui sem mudar lá
 * (ou vice-versa) quebra a consistência entre a mensagem de erro do formulário e o que o backend aceita.
 */
const TIPOS_PDF_OBRIGATORIO = new Set<TipoDocumento>([
  "diploma_graduacao",
  "diploma_pos",
  "diploma_mestrado",
  "diploma_doutorado",
  "certificado_curso",
  "certificacao_profissional",
  "experiencia_ctps",
  "experiencia_declaracao",
  "experiencia_contrato",
  "experiencia_publica",
  "experiencia_autonomo",
  "art_rrt_acervo",
  "declaracao_lideranca",
  "historico_escolar",
  "revalidacao_diploma",
  "traducao_juramentada",
  "curriculo_anexo_v",
]);

export function exigeSomentePdf(tipo: TipoDocumento): boolean {
  return TIPOS_PDF_OBRIGATORIO.has(tipo);
}

export interface Documento {
  id: string;
  inscricao_id: string;
  tipo: TipoDocumento;
  titulo_id: string | null;
  curso_id: string | null;
  vinculo_id: string | null;
  storage_path: string;
  nome_original: string;
  sha256: string;
  mime: string;
  tamanho_bytes: number;
  ativo: boolean;
  enviado_em: string;
}

export type TipoTitulo = "especializacao" | "mestrado" | "doutorado";
export interface Titulo {
  id: string;
  inscricao_id: string;
  tipo: TipoTitulo;
  denominacao: string;
  instituicao: string;
  carga_horaria: number;
  data_conclusao: string;
}

export type TipoCurso = "curso" | "certificacao";
export interface CursoDeclarado {
  id: string;
  inscricao_id: string;
  tipo: TipoCurso;
  denominacao: string;
  instituicao: string;
  carga_horaria: number | null;
  data_conclusao: string;
  numero_credencial: string | null;
  codigo_verificacao: string | null;
}

export type TipoVinculo = "privado" | "publico" | "autonomo";
export interface Vinculo {
  id: string;
  inscricao_id: string;
  tipo: TipoVinculo;
  empregador_contratante: string;
  cargo: string;
  inicio: string;
  fim: string | null;
  ativo: boolean;
  descricao: string;
}

/** Pendência devolvida por publico.verificar_inscricao() (fonte única das regras de envio). */
export interface Pendencia {
  codigo: string;
  mensagem: string;
  etapa: number;
}
