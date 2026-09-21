import { redirect } from "next/navigation";
import { Cabecalho } from "@/components/Cabecalho";
import { createClient } from "@/lib/supabase/server";
import { EntrarForm } from "./EntrarForm";

export const metadata = { title: "Entrar · PSS COMURG 2026" };

export default async function Entrar() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  if (data?.claims) redirect("/inscricao");

  return (
    <>
      <Cabecalho />
      <main className="wrap" style={{ padding: "0 16px 64px" }}>
        <EntrarForm />
      </main>
    </>
  );
}
