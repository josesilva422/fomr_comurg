"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export type PresencaCandidato = "realizada" | "nao_compareceu" | null;

/** Situação do próprio candidato na entrevista técnica (publico.minha_presenca_entrevista); `null` enquanto não houver registro. */
export function useMinhaPresenca(ativo: boolean): PresencaCandidato {
  const [situacao, setSituacao] = useState<PresencaCandidato>(null);
  useEffect(() => {
    if (!ativo) return;
    let vivo = true;
    createClient()
      .schema("publico")
      .rpc("minha_presenca_entrevista")
      .then(({ data }: { data: { situacao: "realizada" | "nao_compareceu" }[] | null }) => {
        if (vivo) setSituacao(data?.[0]?.situacao ?? null);
      });
    return () => {
      vivo = false;
    };
  }, [ativo]);
  return situacao;
}

/** Explicação para o candidato eliminado por ausência (item 6.5.7 do edital). */
export function EliminadoPorAusencia() {
  return (
    <section className="card" style={{ marginTop: 16 }}>
      <h3>Não comparecimento à entrevista técnica</h3>
      <div className="alert alert-err">
        <p>
          Consta o seu não comparecimento à entrevista técnica. Nos termos do <b>item 6.5.7 do edital</b>, é eliminado o candidato que não comparecer à
          entrevista.
        </p>
      </div>
      <p className="hint">
        Em caso de divergência, o recurso é enviado exclusivamente por e-mail, conforme o item 9.2 do edital, dentro do prazo do Anexo IV.
      </p>
    </section>
  );
}
