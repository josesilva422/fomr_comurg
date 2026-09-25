// Relatório de respostas do formulário (Excel e PDF). Uma única lista de "pergunta → resposta" por candidato
// alimenta os dois formatos, para nunca divergirem. Dados vêm de painel.relatorio_respostas().
import { NACIONALIDADES } from "./tipos";
import { GRUPOS, NIVEIS } from "./requisitos";
import { ROTULO_DOCUMENTO, type TipoDocumento } from "./tipos-inscricao";

export interface RegistroRelatorio {
  nome: string;
  cpf: string;
  email: string;
  telefone: string;
  data_nascimento: string;
  nacionalidade: string;
  grupo: "A" | "B" | "C" | null;
  nivel: "junior" | "pleno" | "senior" | null;
  status: string;
  submetida_em: string | null;
  curso_graduacao: string | null;
  grau_graduacao: string | null;
  instituicao_graduacao: string | null;
  data_colacao: string | null;
  formato_diploma: string | null;
  codigo_diploma_digital: string | null;
  diploma_provisorio: boolean;
  diploma_exterior: boolean;
  cota_pcd: boolean;
  data_laudo: string | null;
  cota_racial: boolean;
  solicitou_isencao: boolean;
  hipotese_isencao: string | null;
  nis_isencao: string | null;
  declaracoes_aceitas_em: string | null;
  titulos: { tipo: string; denominacao: string; instituicao: string; carga_horaria: number; data_conclusao: string; tem_documento: boolean }[];
  cursos: {
    tipo: string;
    denominacao: string;
    instituicao: string;
    carga_horaria: number | null;
    data_conclusao: string;
    numero_credencial: string | null;
    codigo_verificacao: string | null;
    tem_documento: boolean;
  }[];
  vinculos: { tipo: string; empregador_contratante: string; cargo: string; inicio: string; fim: string | null; ativo: boolean; descricao: string }[];
  documentos: { tipo: string; nome_original: string; enviado_em: string }[];
}

export interface Secao {
  titulo: string;
  itens: { pergunta: string; resposta: string }[];
}

const FUSO = "America/Sao_Paulo";
const NAO_INFORMADO = "—";

export const fmtCpf = (v: string) => v.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, "$1.$2.$3-$4");
export const fmtTelefone = (v: string) => (v.length === 11 ? v.replace(/^(\d{2})(\d{5})(\d{4})$/, "($1) $2-$3") : v.replace(/^(\d{2})(\d{4})(\d{4})$/, "($1) $2-$3"));
const fmtData = (iso: string | null) => (iso ? iso.slice(0, 10).split("-").reverse().join("/") : NAO_INFORMADO);
const fmtMes = (iso: string | null) => (iso ? iso.slice(0, 7).split("-").reverse().join("/") : NAO_INFORMADO);
export const fmtDataHora = (iso: string | null) =>
  iso ? new Date(iso).toLocaleString("pt-BR", { timeZone: FUSO, dateStyle: "short", timeStyle: "medium" }) : NAO_INFORMADO;
const simNao = (b: boolean) => (b ? "Sim" : "Não");
const texto = (v: string | null | undefined) => (v && v.trim() ? v.trim() : NAO_INFORMADO);

const TIPO_TITULO: Record<string, string> = { especializacao: "Especialização/MBA", mestrado: "Mestrado", doutorado: "Doutorado" };
const TIPO_CURSO: Record<string, string> = { curso: "Curso", certificacao: "Certificação profissional" };
const TIPO_VINCULO: Record<string, string> = { privado: "Setor privado", publico: "Setor público", autonomo: "Autônomo" };
const GRAU: Record<string, string> = { bacharelado: "Bacharelado", licenciatura: "Licenciatura", tecnologico: "Tecnológico" };
const HIPOTESE_ISENCAO: Record<string, string> = { cadunico: "Baixa renda (CadÚnico)", doador_sangue: "Doador de sangue", doador_medula: "Doador de medula óssea" };
const FORMATO: Record<string, string> = { fisico: "Físico", digital: "Digital" };
const STATUS: Record<string, string> = {
  submetida: "Enviada",
  aguardando_isencao: "Enviada — aguardando decisão da isenção",
  homologada: "Aprovada (homologada)",
  indeferida: "Rejeitada (indeferida)",
  cancelada: "Cancelada",
};

const lista = (itens: string[]) => (itens.length ? itens.map((t, i) => `${i + 1}) ${t}`).join("\n") : "Nenhum informado");

/** Perguntas e respostas de um candidato, agrupadas em seções (a ordem é a do formulário). */
export function montarSecoes(r: RegistroRelatorio): Secao[] {
  const nacionalidade = NACIONALIDADES.find((n) => n.valor === r.nacionalidade)?.rotulo ?? r.nacionalidade;
  return [
    {
      titulo: "1. Dados pessoais",
      itens: [
        { pergunta: "Nome completo", resposta: r.nome },
        { pergunta: "CPF", resposta: fmtCpf(r.cpf) },
        { pergunta: "E-mail", resposta: r.email },
        { pergunta: "Telefone", resposta: fmtTelefone(r.telefone) },
        { pergunta: "Data de nascimento", resposta: fmtData(r.data_nascimento) },
        { pergunta: "Nacionalidade", resposta: nacionalidade },
      ],
    },
    {
      titulo: "2. Grupo e nível",
      itens: [
        { pergunta: "Grupo", resposta: r.grupo ? `${GRUPOS[r.grupo].nome} — ${GRUPOS[r.grupo].descricao}` : NAO_INFORMADO },
        { pergunta: "Nível", resposta: r.nivel ? NIVEIS[r.nivel].nome : NAO_INFORMADO },
      ],
    },
    {
      titulo: "3. Formação",
      itens: [
        { pergunta: "Curso de graduação", resposta: texto(r.curso_graduacao) },
        { pergunta: "Grau", resposta: r.grau_graduacao ? (GRAU[r.grau_graduacao] ?? r.grau_graduacao) : NAO_INFORMADO },
        { pergunta: "Instituição de ensino", resposta: texto(r.instituicao_graduacao) },
        { pergunta: "Data de colação de grau", resposta: fmtData(r.data_colacao) },
        { pergunta: "Formato do diploma", resposta: r.formato_diploma ? (FORMATO[r.formato_diploma] ?? r.formato_diploma) : NAO_INFORMADO },
        { pergunta: "Código, QR Code ou endereço de validação do diploma digital (opcional)", resposta: texto(r.codigo_diploma_digital) },
        { pergunta: "Certificado provisório (com histórico escolar)?", resposta: simNao(r.diploma_provisorio) },
        { pergunta: "Diploma obtido no exterior?", resposta: simNao(r.diploma_exterior) },
        {
          pergunta: "Pós-graduação (especialização, mestrado, doutorado)",
          resposta: lista(
            r.titulos.map(
              (t) =>
                `${TIPO_TITULO[t.tipo] ?? t.tipo}: ${t.denominacao} — ${t.instituicao}, ${t.carga_horaria}h, concluído em ${fmtData(t.data_conclusao)}` +
                (t.tem_documento ? "" : " [sem documento anexado]"),
            ),
          ),
        },
        {
          pergunta: "Cursos e certificações",
          resposta: lista(
            r.cursos.map(
              (c) =>
                `${TIPO_CURSO[c.tipo] ?? c.tipo}: ${c.denominacao} — ${c.instituicao}, ${c.carga_horaria ? `${c.carga_horaria}h, ` : ""}concluído em ${fmtData(c.data_conclusao)}` +
                (c.numero_credencial ? `, credencial ${c.numero_credencial}` : "") +
                (c.codigo_verificacao ? `, código de verificação ${c.codigo_verificacao}` : "") +
                (c.tem_documento ? "" : " [sem documento anexado]"),
            ),
          ),
        },
      ],
    },
    {
      titulo: "4. Experiência profissional",
      itens: [
        {
          pergunta: "Vínculos de experiência",
          resposta: lista(
            r.vinculos.map(
              (v) =>
                `${TIPO_VINCULO[v.tipo] ?? v.tipo}: ${v.empregador_contratante} — ${v.cargo}, de ${fmtMes(v.inicio)} a ${v.ativo ? "vínculo ativo" : fmtMes(v.fim)}. Atividades: ${v.descricao}`,
            ),
          ),
        },
      ],
    },
    {
      titulo: "5. Vagas reservadas e isenção",
      itens: [
        { pergunta: "Concorre à vaga de pessoa com deficiência (PcD)?", resposta: simNao(r.cota_pcd) },
        { pergunta: "Data de emissão do laudo médico", resposta: fmtData(r.data_laudo) },
        { pergunta: "Concorre à vaga reservada para candidatos negros?", resposta: simNao(r.cota_racial) },
        { pergunta: "Solicitou isenção da taxa de inscrição?", resposta: simNao(r.solicitou_isencao) },
        { pergunta: "Hipótese de isenção (decreto municipal)", resposta: r.hipotese_isencao ? (HIPOTESE_ISENCAO[r.hipotese_isencao] ?? r.hipotese_isencao) : NAO_INFORMADO },
        { pergunta: "NIS (baixa renda / CadÚnico)", resposta: texto(r.nis_isencao) },
      ],
    },
    {
      titulo: "6. Documentos anexados",
      itens: [
        {
          pergunta: "Documentos enviados",
          resposta: lista(r.documentos.map((d) => `${ROTULO_DOCUMENTO[d.tipo as TipoDocumento] ?? d.tipo} (${d.nome_original})`)),
        },
      ],
    },
    {
      titulo: "7. Conclusão",
      itens: [
        { pergunta: "Declarações aceitas em", resposta: fmtDataHora(r.declaracoes_aceitas_em) },
        { pergunta: "Situação da inscrição", resposta: STATUS[r.status] ?? r.status },
        { pergunta: "Inscrição concluída (enviada) em", resposta: fmtDataHora(r.submetida_em) },
      ],
    },
  ];
}

export function nomeArquivo(prefixo: string, extensao: "xlsx" | "pdf") {
  const agora = new Date().toLocaleString("sv-SE", { timeZone: FUSO }).replace(/[: ]/g, "-").slice(0, 16);
  return `${prefixo}-${agora}.${extensao}`;
}
