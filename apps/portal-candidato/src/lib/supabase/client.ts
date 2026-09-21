import type { Banco } from "./banco";
import { createBrowserClient } from "@supabase/ssr";

// Cliente do navegador. Todas as tabelas do candidato ficam no schema `publico`.
// A proteção real é o RLS no banco; esta chave (publishable) pode ser pública.
export function createClient() {
  return createBrowserClient<Banco, "publico">(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    { db: { schema: "publico" } },
  );
}
