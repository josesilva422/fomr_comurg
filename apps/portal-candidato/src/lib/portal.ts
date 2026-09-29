// Página inicial pública: publicações da Comissão, cronograma (Anexo IV) e vagas (item 2.1).
// O edital (item 13.2) define esta plataforma como o canal oficial dos atos do certame.

export type CategoriaPublicacao = "edital" | "retificacao" | "anexo" | "resultado" | "comunicado" | "outro";

export const CATEGORIAS: Record<CategoriaPublicacao, string> = {
  edital: "Edital",
  retificacao: "Retificação",
  anexo: "Anexo / formulário",
  resultado: "Resultado",
  comunicado: "Comunicado",
  outro: "Outro",
};

export interface PublicacaoPublica {
  id: string;
  categoria: CategoriaPublicacao;
  titulo: string;
  texto: string | null;
  tem_arquivo: boolean;
  arquivo_nome: string | null;
  arquivo_bytes: number | null;
  publicado_em: string;
}

export interface ItemCronograma {
  ordem: number;
  evento: string;
  data_inicio: string | null;
  data_fim: string | null;
  detalhe: string | null;
}

export interface VagaPublica {
  grupo: "A" | "B" | "C";
  nivel: "junior" | "pleno" | "senior";
  quantidade: number;
  remuneracao: number;
}

export type SituacaoEtapa = "concluida" | "andamento" | "futura";

/** Data de hoje no fuso de Brasília, 'AAAA-MM-DD'. */
export const hojeSP = (agora: Date = new Date()) => agora.toLocaleDateString("en-CA", { timeZone: "America/Sao_Paulo" });

const dm = (iso: string) => iso.split("-").reverse().slice(0, 2).join("/");
const dma = (iso: string) => iso.split("-").reverse().join("/");

/** Texto da data como no Anexo IV: intervalo, data única ou "Até ..."; o detalhe (ex.: dias específicos) prevalece. */
export function textoData(c: ItemCronograma): string {
  if (c.detalhe) return c.detalhe;
  if (c.data_inicio && c.data_fim) return c.data_inicio === c.data_fim ? dma(c.data_fim) : `${dm(c.data_inicio)} a ${dma(c.data_fim)}`;
  if (c.data_fim) return /^Publicação do Edital/i.test(c.evento) ? dma(c.data_fim) : `Até ${dma(c.data_fim)}`;
  return `A partir de ${dma(c.data_inicio!)}`;
}

export function situacaoEtapa(c: ItemCronograma, hoje: string): SituacaoEtapa {
  const fim = c.data_fim ?? c.data_inicio!;
  const inicio = c.data_inicio ?? c.data_fim!;
  if (fim < hoje) return "concluida";
  // Itens "Até X" (sem início) só ficam "em andamento" no próprio dia; os com intervalo, durante todo o intervalo.
  if (inicio <= hoje) return "andamento";
  return "futura";
}

export function tamanhoArquivo(bytes: number | null): string {
  if (!bytes) return "";
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1).replace(".", ",")} MB`;
}

/** Publicado há até 3 dias. */
export const ehNovo = (iso: string, agora: Date = new Date()) => agora.getTime() - new Date(iso).getTime() < 3 * 24 * 3600 * 1000;

/** Quantos itens cada lista mostra na página inicial; o restante fica em "Ver todos". */
export const LIMITE_HOME = 3;

/** Grupos de documentos na página inicial e na página de publicações. */
export const GRUPOS_DOCUMENTOS: { chave: string; titulo: string; categorias: CategoriaPublicacao[] }[] = [
  { chave: "edital", titulo: "Edital e retificações", categorias: ["edital", "retificacao"] },
  { chave: "resultados", titulo: "Resultados", categorias: ["resultado"] },
  { chave: "anexos", titulo: "Anexos e formulários", categorias: ["anexo"] },
  { chave: "outros", titulo: "Outros documentos", categorias: ["outro"] },
];

/** Mais recente primeiro; no grupo do edital, o edital fica fixo no topo e as retificações vêm depois. */
export function ordenarDocumentos(lista: PublicacaoPublica[]): PublicacaoPublica[] {
  return [...lista].sort((a, b) => {
    const fa = a.categoria === "edital" ? 0 : 1;
    const fb = b.categoria === "edital" ? 0 : 1;
    if (fa !== fb) return fa - fb;
    return new Date(b.publicado_em).getTime() - new Date(a.publicado_em).getTime();
  });
}
