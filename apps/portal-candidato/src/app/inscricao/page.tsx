import { redirect } from "next/navigation";
import { Cabecalho } from "@/components/Cabecalho";
import { createClient } from "@/lib/supabase/server";
import type { Candidato, Inscricao } from "@/lib/tipos";
import { Assistente } from "./Assistente";

export const metadata = { title: "Minha inscrição · PSS COMURG 2026" };

export default async function PaginaInscricao() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  if (!claims) redirect("/entrar");

  // O RLS devolve somente as linhas do próprio candidato.
  const { data: candidato } = await supabase.from("candidatos").select("*").maybeSingle();
  const { data: inscricao } = await supabase.from("inscricoes").select("*").maybeSingle();

  return (
    <>
      <Cabecalho email={String(claims.email ?? "")} />
      <Assistente
        userId={String(claims.sub)}
        email={String(claims.email ?? "")}
        candidato={(candidato as Candidato | null) ?? null}
        inscricao={(inscricao as Inscricao | null) ?? null}
      />
    </>
  );
}
