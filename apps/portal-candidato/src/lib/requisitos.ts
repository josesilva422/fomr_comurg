// Requisitos por Grupo e Nível (edital, itens 3.2 a 3.4; vagas: item 2.1).
// As LISTAS DE GRADUAÇÃO não ficam aqui: vêm do banco (publico.cursos_aceitos), conferidas com o edital.
import type { Grupo, Nivel } from "./tipos";

export const GRUPOS: Record<Grupo, { nome: string; descricao: string }> = {
  A: { nome: "Grupo A", descricao: "Analista de Projetos e Obras" },
  B: { nome: "Grupo B", descricao: "Governança de Projetos" },
  C: { nome: "Grupo C", descricao: "Analista de Licitações e Conformidade Processual" },
};

export const NIVEIS: Record<Nivel, { nome: string; minAnos: number }> = {
  junior: { nome: "Júnior", minAnos: 1 },
  pleno: { nome: "Pleno", minAnos: 4 },
  senior: { nome: "Sênior", minAnos: 8 },
};

export const VAGAS: Record<Grupo, Record<Nivel, number>> = {
  A: { junior: 1, pleno: 1, senior: 1 },
  B: { junior: 1, pleno: 2, senior: 1 },
  C: { junior: 1, pleno: 1, senior: 1 },
};

export type ModoPos = "nao" | "equiv" | "obrig";
export interface Requisito {
  modo: ModoPos;
  pos?: string;
  equiv?: string;
  atuacao: string;
}

export const REQUISITOS: Record<Grupo, Record<Nivel, Requisito>> = {
  A: {
    junior: {
      modo: "nao",
      atuacao:
        "Obras e construção civil; fiscalização de obras ou contratos; orçamentos; planejamento ou gestão de projetos; licitações de engenharia (qualquer uma delas).",
    },
    pleno: {
      modo: "equiv",
      pos: "Gestão de Obras, Orçamentação, Infraestrutura Urbana, Gerenciamento de Projetos, Engenharia de Custos, Gestão e Fiscalização de Contratos ou áreas diretamente relacionadas",
      equiv: "5 anos de experiência na área substituem a pós-graduação.",
      atuacao:
        "Ao menos 2 dos 4 anos em: fiscalização de obras, elaboração ou análise de projetos de engenharia, planejamento e controle de projetos, orçamento de obras, gestão de contratos de engenharia, licitações de engenharia ou infraestrutura urbana e resíduos sólidos.",
    },
    senior: {
      modo: "obrig",
      pos: "Gestão de Obras, Gerenciamento de Projetos, Engenharia de Custos, Infraestrutura Urbana ou Gestão e Fiscalização de Contratos",
      atuacao:
        "Ao menos 3 dos 8 anos em liderança técnica ou responsabilidade principal, comprovados por declaração específica do contratante.",
    },
  },
  B: {
    junior: {
      modo: "nao",
      atuacao: "Planejamento, gestão de projetos, governança, PMO ou monitoramento e controle de projetos.",
    },
    pleno: {
      modo: "equiv",
      pos: "Gestão de Projetos, Governança Corporativa, Administração Pública, Gestão Estratégica, Planejamento e Controle ou PMO",
      equiv: "Certificação PMP, PgMP, PRINCE2 ou IPMA ativa, ou 5 anos de experiência.",
      atuacao:
        "Ao menos uma das áreas: gestão de projetos, governança de projetos, PMO, planejamento e controle de projetos ou gestão de riscos.",
    },
    senior: {
      modo: "obrig",
      pos: "Gestão de Projetos, Governança Corporativa, Administração Pública, Gestão Estratégica ou PMO",
      atuacao:
        "Experiência em gestão de projetos e portfólio, com ao menos 3 dos 8 anos em liderança técnica ou responsabilidade principal.",
    },
  },
  C: {
    junior: {
      modo: "nao",
      atuacao:
        "Instrução de processos licitatórios; fases preparatórias; auxílio em ETP, TR ou edital; histórico de tramitação processual; análise documental para habilitação e propostas.",
    },
    pleno: {
      modo: "equiv",
      pos: "Direito Administrativo, Licitações e Contratos Administrativos, Gestão Pública, Auditoria e Compliance, Governança no Setor Público ou Contratos e Convênios Públicos",
      equiv: "5 anos em licitações públicas e conformidade.",
      atuacao:
        "Planejamento de licitações, elaboração de editais, julgamento de propostas, padronização de fluxos, controle orçamentário e alinhamento de integridade às diretrizes do TCM-GO.",
    },
    senior: {
      modo: "obrig",
      pos: "Direito Administrativo, Licitações e Contratos Públicos, Governança Pública, Auditoria e Conformidade, Contratos e Convênios Públicos ou Gestão Estratégica no Setor Público",
      atuacao:
        "Experiência em contratações públicas e conformidade processual de projetos de infraestrutura, com ao menos 3 dos 8 anos em responsabilidade técnica principal ou liderança.",
    },
  },
};
