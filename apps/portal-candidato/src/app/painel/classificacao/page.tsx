import Link from "next/link";
import { redirect } from "next/navigation";
import { Cabecalho } from "@/components/Cabecalho";
import { createClient } from "@/lib/supabase/server";
import { ClassificacaoTabela } from "./ClassificacaoTabela";

export const metadata = { title: "Classificação · Painel da Comissão", robots: { index: false, follow: false } };

export default async function ClassificacaoPage() {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) redirect("/painel/entrar");
  const { data: souComissao } = await supabase.schema("painel").rpc("sou_da_comissao");
  if (!souComissao) redirect("/painel");

  return (
    <>
      <Cabecalho email={String(claims.claims.email ?? "")} />
      <main className="wrap" style={{ padding: "24px 16px 64px" }}>
        <Link href="/painel" className="voltar-link">
          ← Voltar para a lista
        </Link>
        <div className="card">
          <header className="step-head">
            <p className="eyebrow">Painel da Comissão</p>
            <h2>Classificação — análise curricular + entrevista</h2>
            <p className="lead">
              PF = AC (máx. 60) + ET (máx. 40), por Grupo e Nível, só com os convocados para a entrevista. Lance as fichas dos avaliadores na página de
              cada candidato. Nada aqui é publicado ao candidato.
            </p>
          </header>
          <ClassificacaoTabela />
        </div>
      </main>
    </>
  );
}
