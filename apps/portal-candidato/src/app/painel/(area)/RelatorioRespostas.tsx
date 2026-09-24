"use client";

import { useState } from "react";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import type { Grupo, Nivel } from "@/lib/tipos";

// Baixa o relatório de respostas do formulário em Excel ou PDF. O servidor exige ao menos um filtro.
export function RelatorioRespostas() {
  const [grupo, setGrupo] = useState<Grupo | "">("");
  const [nivel, setNivel] = useState<Nivel | "">("");
  const [busca, setBusca] = useState("");
  const [baixando, setBaixando] = useState<"xlsx" | "pdf" | null>(null);
  const [erro, setErro] = useState("");

  const temFiltro = Boolean(grupo || nivel || busca.trim());

  async function baixar(formato: "xlsx" | "pdf") {
    setErro("");
    setBaixando(formato);
    try {
      const q = new URLSearchParams({ formato });
      if (grupo) q.set("grupo", grupo);
      if (nivel) q.set("nivel", nivel);
      if (busca.trim()) q.set("busca", busca.trim());
      const res = await fetch(`/api/painel/relatorio?${q.toString()}`);
      if (!res.ok) {
        const corpo = await res.json().catch(() => null);
        throw new Error(corpo?.erro ?? "Não foi possível gerar o relatório.");
      }
      const nome = /filename="([^"]+)"/.exec(res.headers.get("Content-Disposition") ?? "")?.[1] ?? `relatorio.${formato}`;
      const url = URL.createObjectURL(await res.blob());
      const a = document.createElement("a");
      a.href = url;
      a.download = nome;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      setErro(e instanceof Error ? e.message : "Falha ao baixar.");
    } finally {
      setBaixando(null);
    }
  }

  return (
    <div>
      <p className="hint" style={{ margin: "0 0 12px" }}>
        Para conferir o que cada candidato respondeu. Escolha ao menos um filtro — só entram inscrições já enviadas. O
        PDF traz uma página por candidato; o Excel traz uma coluna por pergunta e uma linha por candidato. Cada download
        fica registrado na auditoria.
      </p>
      <div className="filtros-avancados" style={{ marginBottom: 12 }}>
        <select value={grupo} onChange={(e) => setGrupo(e.target.value as Grupo | "")} aria-label="Grupo">
          <option value="">Grupo (todos)</option>
          {(Object.keys(GRUPOS) as Grupo[]).map((g) => (
            <option key={g} value={g}>
              {GRUPOS[g].nome}
            </option>
          ))}
        </select>
        <select value={nivel} onChange={(e) => setNivel(e.target.value as Nivel | "")} aria-label="Nível">
          <option value="">Nível (todos)</option>
          {(Object.keys(NIVEIS) as Nivel[]).map((n) => (
            <option key={n} value={n}>
              {NIVEIS[n].nome}
            </option>
          ))}
        </select>
        <input className="painel-busca" placeholder="Nome ou CPF…" value={busca} onChange={(e) => setBusca(e.target.value)} aria-label="Nome ou CPF" />
      </div>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        <button type="button" className="btn btn-primary" disabled={!temFiltro || baixando !== null} onClick={() => baixar("xlsx")}>
          {baixando === "xlsx" ? "Gerando…" : "Baixar Excel (.xlsx)"}
        </button>
        <button type="button" className="btn btn-primary" disabled={!temFiltro || baixando !== null} onClick={() => baixar("pdf")}>
          {baixando === "pdf" ? "Gerando…" : "Baixar PDF"}
        </button>
      </div>
      {!temFiltro ? <p className="hint" style={{ marginTop: 8 }}>Selecione grupo, nível ou digite nome/CPF para liberar o download.</p> : null}
      {erro ? (
        <div className="alert alert-err" style={{ marginTop: 12 }}>
          <p>{erro}</p>
        </div>
      ) : null}
    </div>
  );
}
