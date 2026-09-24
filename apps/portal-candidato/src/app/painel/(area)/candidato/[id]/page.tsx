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

export default async function CandidatoPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
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
      <DetalheCandidato inscricaoId={id} resumo={resumo} avaliacaoInicial={avaliacao as AvaliacaoDetalhada} />
    </>
  );
}
