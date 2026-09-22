"use client";

import { useRef, useState } from "react";
import type { DadosCurriculo } from "@/lib/openai";

/**
 * Envia o currículo (Anexo V) e pede à IA uma leitura dele. O resultado só é usado para PRÉ-PREENCHER
 * cartões editáveis nas etapas de Formação e Experiência — nada é salvo sozinho; a pessoa confere e
 * clica em "Salvar" (ou remove) cada item, igual a quem preenche na mão.
 */
export function ImportarCurriculo({ aoLido }: { aoLido: (dados: DadosCurriculo) => void }) {
  const entrada = useRef<HTMLInputElement>(null);
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState("");
  const [ok, setOk] = useState(false);

  async function selecionar(arquivo: File | undefined) {
    if (entrada.current) entrada.current.value = "";
    if (!arquivo) return;
    setErro("");
    setOk(false);
    setEnviando(true);
    try {
      const form = new FormData();
      form.append("arquivo", arquivo);
      const r = await fetch("/api/importar-curriculo", { method: "POST", body: form });
      const j = await r.json();
      if (!r.ok) throw new Error(j.erro || "Não foi possível ler o currículo.");
      aoLido(j.dados as DadosCurriculo);
      setOk(true);
    } catch (e) {
      setErro(e instanceof Error ? e.message : "Não foi possível ler o currículo.");
    } finally {
      setEnviando(false);
    }
  }

  return (
    <div className="panel" style={{ marginBottom: 22 }}>
      <h3 style={{ marginTop: 0 }}>Tem um currículo pronto?</h3>
      <p className="hint">
        Envie o seu currículo (PDF, JPG ou PNG) e a IA tenta preencher automaticamente os títulos, cursos e
        vínculos de experiência abaixo — <b>sempre editáveis</b>: nada é salvo até você conferir e clicar em
        &quot;Salvar&quot; em cada item. Também conta como o envio do currículo pedido no Anexo V.
      </p>
      <button type="button" className="btn" disabled={enviando} onClick={() => entrada.current?.click()}>
        {enviando ? <span className="spin" aria-hidden /> : null} {enviando ? "Lendo currículo…" : "Enviar currículo"}
      </button>
      <input ref={entrada} type="file" className="sr-only" tabIndex={-1} accept=".pdf,.jpg,.jpeg,.png" onChange={(e) => void selecionar(e.target.files?.[0])} />
      {erro ? (
        <p className="err" role="alert" style={{ marginTop: 8 }}>
          {erro}
        </p>
      ) : null}
      {ok ? <p className="hint" style={{ marginTop: 8, color: "var(--ok-text)" }}>✓ Currículo lido. Revise os campos preenchidos abaixo antes de salvar.</p> : null}
    </div>
  );
}
