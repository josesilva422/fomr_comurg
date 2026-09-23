import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { AvaliacaoResumo } from "@/lib/pontuacao";
import Link from "next/link";
import { PainelLista } from "./PainelLista";
import { RelatorioRespostas } from "./RelatorioRespostas";

// Atalho de hoje (ver docs/decisoes-pendentes.md, P5): o painel roda nas mesmas rotas/login do portal
// do candidato, liberado só para quem está em interno.usuarios_internos. O CLAUDE.md pede duas áreas
// separadas (app e subdomínio próprios, MFA); isso fica registrado como dívida técnica, não como decisão.
export const metadata = { title: "Painel da Comissão · PSS COMURG 2026", robots: { index: false, follow: false } };

export default async function PainelPage() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  if (!claims) redirect("/painel/entrar");

  const { data: souComissao } = await supabase.schema("painel").rpc("sou_da_comissao");
  if (!souComissao) {
    return (
      <main className="wrap" style={{ padding: "48px 16px" }}>
        <div className="card" style={{ maxWidth: 520, margin: "0 auto", textAlign: "center" }}>
          <h2>Acesso restrito</h2>
          <p className="lead" style={{ marginTop: 8 }}>
            Esta área é reservada à Comissão Organizadora. A conta <b>{String(claims.email ?? "")}</b> não está autorizada.
          </p>
        </div>
      </main>
    );
  }

  const { data: avaliacoes, error } = await supabase.schema("painel").rpc("listar_avaliacoes");

  return (
    <main className="wrap" style={{ padding: "24px 16px 64px" }}>
      <div style={{ margin: "0 0 16px" }}>
        <Link href="/painel/classificacao" className="btn btn-primary">
          Classificação final (AC + entrevista)
        </Link>
      </div>
      <RelatorioRespostas />
      <div className="card">
        <header className="step-head">
          <p className="eyebrow">Painel da Comissão</p>
          <h2>Análise curricular — resultado calculado</h2>
          <p className="lead">
            Pontuação calculada automaticamente pelo motor de regras (rascunho). Nenhum resultado é definitivo até
            revisão e aprovação da Comissão. Clique num candidato para ver o detalhamento por critério. A coluna
            &quot;Convocação&quot; segue os itens 6.4.4 e 6.5.1 (AC ≥ 35 pts, até 3 candidatos por vaga, com empate
            na última posição).
          </p>
        </header>
        {error ? (
          <div className="alert alert-err">
            <p>Não foi possível carregar os dados: {error.message}</p>
          </div>
        ) : (
          <PainelLista avaliacoes={(avaliacoes as AvaliacaoResumo[] | null) ?? []} />
        )}
      </div>
    </main>
  );
}
