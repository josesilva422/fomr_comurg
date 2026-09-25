"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { COMPETENCIAS, TOTAL_ENTREVISTA, faixa, type ChaveCompetencia, type FichaEntrevista } from "@/lib/entrevista";

type Campos = Record<ChaveCompetencia, string>;
const vazio = (): Campos => ({ dominio: "", analise: "", planejamento: "", comunicacao: "", caso: "", postura: "" });

function camposDe(f: FichaEntrevista | null): { notas: Campos; justs: Campos } {
  if (!f) return { notas: vazio(), justs: vazio() };
  return {
    notas: {
      dominio: String(f.nota_dominio), analise: String(f.nota_analise), planejamento: String(f.nota_planejamento),
      comunicacao: String(f.nota_comunicacao), caso: String(f.nota_caso), postura: String(f.nota_postura),
    },
    justs: {
      dominio: f.just_dominio, analise: f.just_analise, planejamento: f.just_planejamento,
      comunicacao: f.just_comunicacao, caso: f.just_caso, postura: f.just_postura,
    },
  };
}

// Ficha do PRÓPRIO avaliador logado (Anexo II, Parte 2): nota inteira por competência + justificativa obrigatória.
// O banco grava a ficha no login de quem salva; ninguém vê a ficha de outro avaliador (edital 6.5.5).
export function FichaAvaliador({
  inscricaoId,
  minhaFicha,
  limiteAtingido,
  aoSalvar,
}: {
  inscricaoId: string;
  minhaFicha: FichaEntrevista | null;
  /** Candidato já tem o máximo de fichas e esta pessoa ainda não tem a sua. */
  limiteAtingido: boolean;
  aoSalvar: () => void;
}) {
  const inicial = camposDe(minhaFicha);
  const [notas, setNotas] = useState<Campos>(inicial.notas);
  const [justs, setJusts] = useState<Campos>(inicial.justs);
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState("");
  const [aviso, setAviso] = useState("");

  const somaTotal = COMPETENCIAS.reduce((s, c) => s + (Number(notas[c.chave]) || 0), 0);

  async function salvar() {
    setErro("");
    setAviso("");
    for (const c of COMPETENCIAS) {
      const n = Number(notas[c.chave]);
      if (notas[c.chave] === "" || !Number.isInteger(n) || n < 0 || n > c.peso) return setErro(`"${c.rotulo}": use um número inteiro de 0 a ${c.peso}.`);
      if (justs[c.chave].trim().length < 3) return setErro(`Escreva a justificativa de "${c.rotulo}".`);
    }
    setSalvando(true);
    const { error } = await createClient().schema("painel").rpc("salvar_ficha_entrevista", {
      p_inscricao_id: inscricaoId,
      p_notas: Object.fromEntries(COMPETENCIAS.map((c) => [c.chave, Number(notas[c.chave])])),
      p_justificativas: Object.fromEntries(COMPETENCIAS.map((c) => [c.chave, justs[c.chave].trim()])),
    });
    setSalvando(false);
    if (error) return setErro(error.message);
    setAviso(minhaFicha ? "Sua ficha foi corrigida." : "Sua ficha foi enviada.");
    aoSalvar();
  }

  async function remover() {
    const motivo = window.prompt("Remover a sua ficha deste candidato? Informe o motivo (fica na auditoria):");
    if (!motivo) return;
    const { error } = await createClient().schema("painel").rpc("remover_minha_ficha", { p_inscricao_id: inscricaoId, p_motivo: motivo });
    if (error) return setErro(error.message);
    setNotas(vazio());
    setJusts(vazio());
    aoSalvar();
  }

  if (limiteAtingido && !minhaFicha) {
    return (
      <div className="alert alert-info">
        <p>Este candidato já tem o número máximo de fichas. Não é possível enviar uma nova.</p>
      </div>
    );
  }

  return (
    <div className="card" style={{ marginTop: 12 }}>
      <h4 style={{ marginTop: 0 }}>{minhaFicha ? "Minha ficha (enviada — pode corrigir)" : "Minha ficha"}</h4>
      <p className="hint">
        Só você vê as suas notas. Os outros avaliadores e a Comissão veem apenas que a sua ficha foi enviada e, com pelo menos 3 fichas, a média.
      </p>
      {COMPETENCIAS.map((c) => {
        const n = Number(notas[c.chave]);
        const ok = notas[c.chave] !== "" && Number.isInteger(n) && n >= 0 && n <= c.peso;
        return (
          <div key={c.chave} className="field" style={{ marginBottom: 14 }}>
            <label htmlFor={`n-${inscricaoId}-${c.chave}`}>
              {c.rotulo} <span className="hint">(peso {c.peso})</span>
              {ok ? <span className="hint"> — {faixa(n, c.peso)}</span> : null}
            </label>
            <input
              id={`n-${inscricaoId}-${c.chave}`}
              type="number"
              min={0}
              max={c.peso}
              step={1}
              inputMode="numeric"
              value={notas[c.chave]}
              onChange={(e) => setNotas({ ...notas, [c.chave]: e.target.value })}
              style={{ maxWidth: 120 }}
              placeholder={`0 a ${c.peso}`}
            />
            <textarea
              aria-label={`Justificativa — ${c.rotulo}`}
              value={justs[c.chave]}
              onChange={(e) => setJusts({ ...justs, [c.chave]: e.target.value })}
              placeholder="Justifique"
              style={{ marginTop: 6, minHeight: 64 }}
            />
          </div>
        );
      })}
      <p className="hint">
        Total da minha ficha: <b>{somaTotal}</b> de {TOTAL_ENTREVISTA}
      </p>
      {erro ? (
        <div className="alert alert-err">
          <p>{erro}</p>
        </div>
      ) : null}
      {aviso ? (
        <div className="alert alert-ok">
          <p>{aviso}</p>
        </div>
      ) : null}
      <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
        <button type="button" className="btn btn-primary" disabled={salvando} onClick={salvar}>
          {salvando ? "Salvando…" : minhaFicha ? "Salvar correção" : "Enviar minha ficha"}
        </button>
        {minhaFicha ? (
          <button type="button" className="btn btn-ghost" disabled={salvando} onClick={remover}>
            Remover minha ficha
          </button>
        ) : null}
      </div>
    </div>
  );
}
