import { redirect } from "next/navigation";
import { Cabecalho } from "@/components/Cabecalho";
import { createClient } from "@/lib/supabase/server";
import { PainelNav } from "./PainelNav";

// Atalho de hoje (ver docs/decisoes-pendentes.md, P5): o painel roda nas mesmas rotas/login do portal
// do candidato, liberado só para quem está em interno.usuarios_internos. O CLAUDE.md pede duas áreas
// separadas (app e subdomínio próprios, MFA); isso fica registrado como dívida técnica, não como decisão.
export default async function PainelLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  if (!claims) redirect("/painel/entrar");
  const email = String(claims.email ?? "");

  const { data: souComissao } = await supabase.schema("painel").rpc("sou_da_comissao");
  if (!souComissao) {
    return (
      <>
        <Cabecalho email={email} />
        <main className="wrap" style={{ padding: "48px 16px" }}>
          <div className="card" style={{ maxWidth: 520, margin: "0 auto", textAlign: "center" }}>
            <h2>Acesso restrito</h2>
            <p className="lead" style={{ marginTop: 8 }}>
              Esta área é reservada à Comissão Organizadora. A conta <b>{email}</b> não está autorizada.
            </p>
          </div>
        </main>
      </>
    );
  }

  return (
    <>
      <Cabecalho email={email} />
      <div className="painel-shell">
        <PainelNav />
        <main className="painel-conteudo">{children}</main>
      </div>
    </>
  );
}
