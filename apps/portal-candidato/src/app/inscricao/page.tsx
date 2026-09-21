import { redirect } from "next/navigation";
import { Cabecalho } from "@/components/Cabecalho";
import { createClient } from "@/lib/supabase/server";
import type { Candidato, Inscricao } from "@/lib/tipos";
import type { CursoDeclarado, Documento, Pendencia, Titulo, Vinculo } from "@/lib/tipos-inscricao";
import { Assistente } from "./Assistente";

export const metadata = { title: "Minha inscrição · PSS COMURG 2026" };

export default async function PaginaInscricao() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  if (!claims) redirect("/entrar");

  // O RLS devolve somente as linhas do próprio candidato.
  const [c, i, d, t, k, v, p] = await Promise.all([
    supabase.from("candidatos").select("*").maybeSingle(),
    supabase.from("inscricoes").select("*").maybeSingle(),
    supabase.from("documentos").select("*").eq("ativo", true).order("enviado_em"),
    supabase.from("titulos_declarados").select("*").order("created_at"),
    supabase.from("cursos_declarados").select("*").order("created_at"),
    supabase.from("vinculos_declarados").select("*").order("inicio"),
    supabase.rpc("verificar_inscricao"),
  ]);

  return (
    <>
      <Cabecalho email={String(claims.email ?? "")} />
      <Assistente
        userId={String(claims.sub)}
        email={String(claims.email ?? "")}
        candidato={(c.data as Candidato | null) ?? null}
        inscricao={(i.data as Inscricao | null) ?? null}
        documentos={(d.data as Documento[] | null) ?? []}
        titulos={(t.data as Titulo[] | null) ?? []}
        cursos={(k.data as CursoDeclarado[] | null) ?? []}
        vinculos={(v.data as Vinculo[] | null) ?? []}
        pendencias={(p.data as Pendencia[] | null) ?? []}
      />
    </>
  );
}
