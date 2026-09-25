"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { montarSecoes, type RegistroRelatorio } from "@/lib/relatorio";

// Quadro recolhível com as respostas do próprio candidato (mesmas perguntas do relatório da Comissão).
// Os dados só são buscados quando o candidato abre o quadro.
export function MeuFormulario() {
  const [registro, setRegistro] = useState<RegistroRelatorio | null>(null);
  const [erro, setErro] = useState("");
  const [buscou, setBuscou] = useState(false);

  async function aoAbrir(aberto: boolean) {
    if (!aberto || buscou) return;
    setBuscou(true);
    const { data, error } = await createClient().rpc("meu_formulario");
    if (error) setErro("Não foi possível carregar o formulário. Tente de novo mais tarde.");
    else setRegistro(data as RegistroRelatorio);
  }

  return (
    <details className="card" style={{ marginTop: 16 }} onToggle={(e) => void aoAbrir((e.currentTarget as HTMLDetailsElement).open)}>
      <summary style={{ cursor: "pointer", fontWeight: 700 }}>Ver as respostas do meu formulário</summary>
      <div style={{ marginTop: 12 }}>
        {erro ? (
          <p className="err">{erro}</p>
        ) : !registro ? (
          <p className="hint">Carregando…</p>
        ) : (
          montarSecoes(registro).map((s) => (
            <section key={s.titulo} style={{ marginBottom: 16 }}>
              <h4 style={{ margin: "0 0 6px" }}>{s.titulo}</h4>
              <dl>
                {s.itens.map((i) => (
                  <div className="kv" key={i.pergunta}>
                    <dt>{i.pergunta}</dt>
                    <dd style={{ whiteSpace: "pre-line" }}>{i.resposta}</dd>
                  </div>
                ))}
              </dl>
            </section>
          ))
        )}
        <p className="hint" style={{ margin: 0 }}>
          A inscrição foi enviada e não pode mais ser alterada (itens 5.5.3 e 9.4 do edital).
        </p>
      </div>
    </details>
  );
}
