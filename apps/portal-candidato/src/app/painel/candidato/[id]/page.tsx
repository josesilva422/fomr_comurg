import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { Cabecalho } from "@/components/Cabecalho";
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
}

export default async function CandidatoPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) redirect("/painel/entrar");

  const { data: souComissao } = await supabase.schema("painel").rpc("sou_da_comissao");
  if (!souComissao) redirect("/painel");

  const [{ data: resumoLista, error: erroResumo }, { data: avaliacao, error: erroAvaliacao }] = await Promise.all([
    supabase.schema("painel").rpc("candidato_resumo", { p_inscricao_id: id }),
    supabase.schema("painel").rpc("avaliacao_detalhada", { p_inscricao_id: id }),
  ]);
  const resumo = (resumoLista as ResumoBanco[] | null)?.[0];
  if (erroResumo || erroAvaliacao || !resumo) notFound();

  return (
    <>
      <Cabecalho email={String(claims.claims.email ?? "")} />
      <main className="wrap" style={{ padding: "24px 16px 64px" }}>
        <Link href="/painel" className="voltar-link">
          ← Voltar para a lista
        </Link>
        <div className="card">
          <DetalheCandidato inscricaoId={id} resumo={resumo} avaliacaoInicial={avaliacao as AvaliacaoDetalhada} />
        </div>
      </main>
    </>
  );
}
