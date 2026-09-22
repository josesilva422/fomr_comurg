"use client";

import { useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { removerDocumento } from "@/lib/armazenamento";
import type { DadosCurriculo } from "@/lib/openai";
import type { Documento } from "@/lib/tipos-inscricao";

/**
 * Envia o currículo (Anexo V) e pede à IA uma leitura dele. O resultado só é usado para PRÉ-PREENCHER
 * cartões editáveis nas etapas de Formação e Experiência — nada é salvo sozinho; a pessoa confere e
 * clica em "Salvar" (ou remove) cada item, igual a quem preenche na mão.
 *
 * Só permite UM currículo ativo por vez (pedido do responsável, 22/09/2026): depois de lido, o botão de
 * envio some — só reaparece se a pessoa remover o currículo atual (por exemplo, se enviou o arquivo errado).
 */
export function ImportarCurriculo({
  documentoAtual,
  aoLido,
  aoMudar,
}: {
  documentoAtual: Documento | undefined;
  aoLido: (dados: DadosCurriculo) => void;
  aoMudar: () => Promise<unknown>;
}) {
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
      await aoMudar();
    } catch (e) {
      setErro(e instanceof Error ? e.message : "Não foi possível ler o currículo.");
    } finally {
      setEnviando(false);
    }
  }

  async function remover() {
    if (!documentoAtual) return;
    setErro("");
    setEnviando(true);
    const msg = await removerDocumento(createClient(), documentoAtual.id);
    if (msg) setErro(msg);
    await aoMudar();
    setEnviando(false);
  }

  return (
    <div className="panel" style={{ marginBottom: 22 }}>
      <h3 style={{ marginTop: 0 }}>Tem um currículo pronto?</h3>
      <p className="hint">
        Envie o seu currículo em <b>PDF</b> e a IA tenta preencher automaticamente os títulos, cursos e
        vínculos de experiência abaixo — <b>sempre editáveis</b>: nada é salvo até você conferir e clicar em
        &quot;Salvar&quot; em cada item. Também conta como o envio do currículo pedido no Anexo V. Só é
        considerado <b>um currículo</b> por inscrição.
      </p>

      {documentoAtual ? (
        <div className="upload">
          <ul className="files" style={{ marginTop: 0 }}>
            <li>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" />
                <path d="M14 3v5h5" />
              </svg>
              <span className="file-name">{documentoAtual.nome_original}</span>
              <button type="button" className="icon-btn" disabled={enviando} aria-label="Remover currículo" onClick={() => void remover()}>
                ×
              </button>
            </li>
          </ul>
          <p className="hint" style={{ marginTop: 8, color: "var(--ok-text)" }}>
            ✓ Currículo enviado. Remova para enviar outro (por exemplo, se anexou o arquivo errado).
          </p>
        </div>
      ) : (
        <button type="button" className="btn" disabled={enviando} onClick={() => entrada.current?.click()}>
          {enviando ? <span className="spin" aria-hidden /> : null} {enviando ? "Lendo currículo…" : "Enviar currículo"}
        </button>
      )}
      <input ref={entrada} type="file" className="sr-only" tabIndex={-1} accept=".pdf" onChange={(e) => void selecionar(e.target.files?.[0])} />
      {erro ? (
        <p className="err" role="alert" style={{ marginTop: 8 }}>
          {erro}
        </p>
      ) : null}
      {ok && !documentoAtual ? <p className="hint" style={{ marginTop: 8, color: "var(--ok-text)" }}>✓ Currículo lido. Revise os campos preenchidos abaixo antes de salvar.</p> : null}
    </div>
  );
}
