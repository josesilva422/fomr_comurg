import { createClient } from "@/lib/supabase/server";
import type { AvaliacaoResumo } from "@/lib/pontuacao";
import { PainelLista } from "./PainelLista";

export const metadata = { title: "Análise curricular · Painel da Comissão", robots: { index: false, follow: false } };

export default async function PainelPage() {
  const supabase = await createClient();
  const { data: avaliacoes, error } = await supabase.schema("painel").rpc("listar_avaliacoes");

  return (
    <div className="card">
      <header className="step-head">
        <p className="eyebrow">Classificação final · Análise curricular</p>
        <h2>Análise curricular — resultado calculado</h2>
        <p className="lead">
          Pontuação calculada automaticamente pelo motor de regras (rascunho). Nenhum resultado é definitivo até revisão e aprovação da Comissão. Clique
          num candidato para ver o detalhamento, o formulário respondido, os documentos e a entrevista. A coluna &quot;Convocação&quot; segue os itens 6.4.4 e
          6.5.1 (AC ≥ 35 pts, até 3 candidatos por vaga, com empate na última posição).
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
  );
}
