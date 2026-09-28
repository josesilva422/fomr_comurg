"use client";

import { useState } from "react";
import { Pendencias } from "@/components/Pendencias";
import { createClient } from "@/lib/supabase/client";
import { traduzirErro } from "@/lib/validacao";
import type { Contexto } from "./contexto";
import { DECLARACOES, VERSAO_DECLARACOES } from "./declaracoes";

// Etapa 7 · Declarações: o candidato lê e marca cada item. Ao continuar, o aceite é gravado (publico.aceitar_declaracoes) e a
// pendência "declaracoes_nao_aceitas" some. A Revisão e envio (etapa 8) vem depois.
export function PassoDeclaracoes({ ctx }: { ctx: Contexto }) {
  const jaAceitas = Boolean(ctx.inscricao?.declaracoes_aceitas_em);
  const [marcadas, setMarcadas] = useState<boolean[]>(() => DECLARACOES.map(() => jaAceitas));
  const [erro, setErro] = useState("");
  const [salvando, setSalvando] = useState(false);
  const [tentou, setTentou] = useState(false);
  const faltam = tentou ? ctx.pendencias.filter((p) => p.etapa === 7) : [];

  async function continuar() {
    setErro("");
    setTentou(true);
    if (marcadas.some((m) => !m)) return setErro("Marque todas as declarações para continuar.");
    setSalvando(true);
    const { error } = await createClient().rpc("aceitar_declaracoes", { p_versao: VERSAO_DECLARACOES });
    if (error) {
      setSalvando(false);
      return setErro(traduzirErro(error));
    }
    await ctx.recarregar();
    setSalvando(false);
    ctx.irPara(8);
  }

  return (
    <section className="card step">
      <header className="step-head">
        <p className="eyebrow">Etapa 7 de 8</p>
        <h2>Declarações</h2>
        <p className="lead">Leia e marque cada item. Sem o aceite de todas as declarações, a inscrição não pode ser enviada.</p>
      </header>

      {DECLARACOES.map((texto, idx) => (
        <div className="decl" key={idx}>
          <label className="check">
            <input
              type="checkbox"
              checked={marcadas[idx]}
              onChange={(e) =>
                setMarcadas((m) => {
                  const novo = [...m];
                  novo[idx] = e.target.checked;
                  return novo;
                })
              }
            />
            <span dangerouslySetInnerHTML={{ __html: idx === 4 ? `${texto} <em>(Texto provisório, a validar com o jurídico e o DPO.)</em>` : texto }} />
          </label>
        </div>
      ))}

      <Pendencias itens={faltam} />
      {erro ? (
        <div className="alert alert-err" role="alert">
          <p>{erro}</p>
        </div>
      ) : null}
      <div className="acoes-form">
        <button type="button" className="btn btn-primary" disabled={salvando} onClick={() => void continuar()}>
          {salvando ? <span className="spin" aria-hidden /> : null} Salvar e continuar →
        </button>
      </div>
    </section>
  );
}
