// Tipos do schema `publico` (espelham as tabelas em supabase/migrations).
export type Grupo = "A" | "B" | "C";
export type Nivel = "junior" | "pleno" | "senior";
export type Nacionalidade = "brasileiro_nato" | "brasileiro_naturalizado" | "portugues";
export type StatusInscricao =
  | "rascunho"
  | "submetida"
  | "aguardando_isencao"
  | "homologada"
  | "indeferida"
  | "cancelada";

export interface Candidato {
  id: string;
  user_id: string;
  nome: string;
  cpf: string;
  email: string;
  telefone: string;
  data_nascimento: string;
  nacionalidade: Nacionalidade;
}

export interface Inscricao {
  id: string;
  candidato_id: string;
  grupo: Grupo | null;
  nivel: Nivel | null;
  status: StatusInscricao;
  curso_graduacao: string | null;
  grau_graduacao: "bacharelado" | "licenciatura" | "tecnologico" | null;
  instituicao_graduacao: string | null;
  data_colacao: string | null;
  formato_diploma: "fisico" | "digital" | null;
  codigo_diploma_digital: string | null;
  diploma_provisorio: boolean;
  diploma_exterior: boolean;
  cota_pcd: boolean;
  data_laudo: string | null;
  cota_racial: boolean;
  solicitou_isencao: boolean;
  justificativa_isencao: string | null;
  declaracoes_aceitas_em: string | null;
  submetida_em: string | null;
}

export const NACIONALIDADES: { valor: Nacionalidade; rotulo: string }[] = [
  { valor: "brasileiro_nato", rotulo: "Brasileiro(a) nato(a)" },
  { valor: "brasileiro_naturalizado", rotulo: "Brasileiro(a) naturalizado(a)" },
  { valor: "portugues", rotulo: "Português(a) com direitos políticos" },
];
