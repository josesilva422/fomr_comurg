import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { AvaliacaoDetalhada } from "@/lib/pontuacao";
import type { Grupo, Nivel } from "@/lib/tipos";
import { DetalheCandidato } from "./DetalheCandidato";

export const metadata = { title: "Candidato · Painel da Comissão", robots: { index: false, follow: false } };

interface ResumoBanco {
  nome: string;
  cpf: string;
  email: string;
  telefone: string;
  grupo: Grupo;
  nivel: Nivel;
  status: string;
  submetida_em: string | null;
  curso_graduacao: string | null;
  grau_graduacao: "bacharelado" | "licenciatura" | "tecnologico" | null;
  instituicao_graduacao: string | null;
  data_colacao: string | null;
  formato_diploma: "fisico" | "digital" | null;
  codigo_diploma_digital: string | null;
  diploma_provisorio: boolean;
  diploma_exterior: boolean;
  cota_pcd: boolean;
  cota_racial: boolean;
  solicitou_isencao: boolean;
}

const ABAS_VALIDAS = ["analise", "entrevista", "formulario", "documentos"] as const;

export default async function CandidatoPage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ aba?: string }> }) {
  const { id } = await params;
  const { aba } = await searchParams;
  const abaInicial = ABAS_VALIDAS.find((a) => a === aba) ?? "analise";
  const supabase = await createClient();
  const [{ data: resumoLista, error: erroResumo }, { data: avaliacao, error: erroAvaliacao }] = await Promise.all([
    supabase.schema("painel").rpc("candidato_resumo", { p_inscricao_id: id }),
    supabase.schema("painel").rpc("avaliacao_detalhada", { p_inscricao_id: id }),
  ]);
  const resumo = (resumoLista as ResumoBanco[] | null)?.[0];
  if (erroResumo || erroAvaliacao || !resumo) notFound();

  return (
    <>
      <Link href="/painel" className="voltar-link">
        ← Voltar para a lista
      </Link>
      <DetalheCandidato abaInicial={abaInicial} inscricaoId={id} resumo={resumo} avaliacaoInicial={avaliacao as AvaliacaoDetalhada} />
    </>
  );
}
