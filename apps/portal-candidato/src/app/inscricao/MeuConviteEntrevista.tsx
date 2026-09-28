"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { dataPorExtenso } from "@/lib/convite-entrevista";

export interface ConviteEntrevista {
  titulo: string;
  data: string;
  horario: string;
  link: string;
  orientacoes: string | null;
  enviado_em: string;
}

/** Último convite do próprio candidato (publico.meu_convite_entrevista); `null` enquanto não houver convite. */
export function useMeuConvite(ativo: boolean): ConviteEntrevista | null {
  const [convite, setConvite] = useState<ConviteEntrevista | null>(null);
  useEffect(() => {
    if (!ativo) return;
    let vivo = true;
    createClient()
      .schema("publico")
      .rpc("meu_convite_entrevista")
      .then(({ data }: { data: ConviteEntrevista[] | null }) => {
        if (vivo) setConvite(data?.[0] ?? null);
      });
    return () => {
      vivo = false;
    };
  }, [ativo]);
  return convite;
}

// Convite para a entrevista técnica enviado pela Comissão (item 6.5.1). Aparece só quando existe; o mesmo conteúdo vai
// por e-mail. Um convite novo substitui o anterior.
export function MeuConviteEntrevista({ convite }: { convite: ConviteEntrevista | null }) {
  if (!convite) return null;
  return (
    <section className="card" style={{ marginTop: 16 }}>
      <details className="recolher" open>
        <summary>
          <span className="recolher-triangulo" aria-hidden />
          <h3>Convocação para a entrevista técnica</h3>
        </summary>
        <div className="recolher-corpo">
          <div className="alert alert-ok" style={{ flexDirection: "column", gap: 0 }}>
            <p>
              <b>{convite.titulo}</b>
            </p>
            <p>
              <b>Data e horário:</b> {dataPorExtenso(convite.data)}, às {convite.horario} (horário de Brasília)
            </p>
            <p style={{ wordBreak: "break-all" }}>
              <b>Link da reunião:</b>{" "}
              <a href={convite.link} target="_blank" rel="noopener noreferrer">
                {convite.link}
              </a>
            </p>
          </div>
          {convite.orientacoes ? (
            <>
              <p style={{ marginBottom: 4 }}>
                <b>Orientações da Comissão:</b>
              </p>
              <p style={{ marginTop: 0, whiteSpace: "pre-line" }}>{convite.orientacoes}</p>
            </>
          ) : null}
          <p className="hint">
            A entrevista é conduzida por banca de, no mínimo, 3 avaliadores (item 6.5.2) e registrada em ata, podendo ser gravada em áudio e vídeo (item
            6.5.6). O não comparecimento elimina o candidato (item 6.5.7).
          </p>
        </div>
      </details>
    </section>
  );
}
