import { redirect } from "next/navigation";
import { Cabecalho } from "@/components/Cabecalho";
import { createClient } from "@/lib/supabase/server";
import { EntrarPainelForm } from "./EntrarPainelForm";

export const metadata = { title: "Acesso da Comissão · PSS COMURG 2026", robots: { index: false, follow: false } };

export default async function EntrarPainel() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  if (data?.claims) {
    const { data: souComissao } = await supabase.schema("painel").rpc("sou_da_comissao");
    if (souComissao) redirect("/painel");
  }

  return (
    <>
      <Cabecalho />
      <main className="wrap" style={{ padding: "0 16px 64px" }}>
        <EntrarPainelForm />
      </main>
    </>
  );
}
