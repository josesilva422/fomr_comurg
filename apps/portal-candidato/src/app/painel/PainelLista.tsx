"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import type { AvaliacaoResumo } from "@/lib/pontuacao";

const fmtCPF = (v: string) => v.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4");

export function PainelLista({ avaliacoes }: { avaliacoes: AvaliacaoResumo[] }) {
  const router = useRouter();
  const [filtro, setFiltro] = useState<"todos" | "habilitados" | "inabilitados">("todos");
  const [busca, setBusca] = useState("");

  const linhas = useMemo(() => {
    const termo = busca.trim().toLowerCase();
    return avaliacoes
      .filter((a) => (filtro === "todos" ? true : filtro === "habilitados" ? a.habilitado : !a.habilitado))
      .filter((a) => !termo || a.nome.toLowerCase().includes(termo) || a.cpf.includes(termo.replace(/\D/g, "")))
      .sort((a, b) => b.total - a.total);
  }, [avaliacoes, filtro, busca]);

  if (!avaliacoes.length) return <div className="empty">Nenhuma inscrição enviada até o momento.</div>;

  return (
    <div>
      <div className="painel-toolbar">
        <div className="painel-tabs">
          {(["todos", "habilitados", "inabilitados"] as const).map((f) => (
            <button key={f} type="button" className={`btn btn-sm${filtro === f ? " btn-primary" : ""}`} onClick={() => setFiltro(f)}>
              {f === "todos" ? `Todos (${avaliacoes.length})` : f === "habilitados" ? `Habilitados (${avaliacoes.filter((a) => a.habilitado).length})` : `Inabilitados (${avaliacoes.filter((a) => !a.habilitado).length})`}
            </button>
          ))}
        </div>
        <input className="painel-busca" placeholder="Buscar por nome ou CPF…" value={busca} onChange={(e) => setBusca(e.target.value)} aria-label="Buscar candidato" />
      </div>

      {linhas.length === 0 ? (
        <div className="empty">Nenhum candidato encontrado com esse filtro.</div>
      ) : (
        <div className="tabela-wrap">
          <table className="tabela">
            <thead>
              <tr>
                <th>Candidato</th>
                <th>Grupo · Nível</th>
                <th>Situação</th>
                <th style={{ textAlign: "right" }}>Formação</th>
                <th style={{ textAlign: "right" }}>Cursos</th>
                <th style={{ textAlign: "right" }}>Experiência</th>
                <th style={{ textAlign: "right" }}>Total</th>
              </tr>
            </thead>
            <tbody>
              {linhas.map((a) => (
                <tr key={a.inscricao_id} onClick={() => router.push(`/painel/candidato/${a.inscricao_id}`)} tabIndex={0}>
                  <td>
                    <strong>{a.nome}</strong>
                    <br />
                    <small className="hint">{fmtCPF(a.cpf)}</small>
                  </td>
                  <td>
                    {GRUPOS[a.grupo].nome} · {NIVEIS[a.nivel].nome}
                  </td>
                  <td>
                    <span className={`pill ${a.habilitado ? "pill-ok" : "pill-err"}`}>{a.habilitado ? "Habilitado" : "Inabilitado"}</span>
                    {a.status === "aguardando_isencao" ? <div className="hint" style={{ marginTop: 4 }}>Aguardando isenção</div> : null}
                  </td>
                  <td style={{ textAlign: "right" }}>{a.pontos_formacao.toFixed(1)}</td>
                  <td style={{ textAlign: "right" }}>{a.pontos_cursos.toFixed(1)}</td>
                  <td style={{ textAlign: "right" }}>{a.pontos_experiencia.toFixed(1)}</td>
                  <td className="col-total" style={{ textAlign: "right" }}>
                    {a.total.toFixed(1)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
