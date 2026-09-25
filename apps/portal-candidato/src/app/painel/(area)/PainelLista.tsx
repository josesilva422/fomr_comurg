"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import type { Grupo, Nivel } from "@/lib/tipos";
import type { AvaliacaoResumo } from "@/lib/pontuacao";
import { ConviteEntrevista } from "./entrevista/ConviteEntrevista";

interface ResumoConvite {
  inscricao_id: string;
  data: string;
  horario: string;
  email_enviado: boolean | null;
}

const fmtCPF = (v: string) => v.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4");
const fmtDia = (iso: string) => iso.split("-").reverse().join("/");

export function PainelLista({ avaliacoes }: { avaliacoes: AvaliacaoResumo[] }) {
  const router = useRouter();
  const [habilitacao, setHabilitacao] = useState<"todos" | "habilitados" | "inabilitados">("todos");
  const [grupo, setGrupo] = useState<Grupo | "todos">("todos");
  const [nivel, setNivel] = useState<Nivel | "todos">("todos");
  const [soConvocaveis, setSoConvocaveis] = useState(false);
  const [busca, setBusca] = useState("");
  const [convites, setConvites] = useState<Record<string, ResumoConvite>>({});
  const [versaoConvites, setVersaoConvites] = useState(0);

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("convites_entrevista_resumo")
      .then(({ data }: { data: ResumoConvite[] | null }) => setConvites(Object.fromEntries((data ?? []).map((c) => [c.inscricao_id, c]))));
  }, [versaoConvites]);

  const linhas = useMemo(() => {
    const termo = busca.trim().toLowerCase();
    return avaliacoes
      .filter((a) => (habilitacao === "todos" ? true : habilitacao === "habilitados" ? a.habilitado : !a.habilitado))
      .filter((a) => grupo === "todos" || a.grupo === grupo)
      .filter((a) => nivel === "todos" || a.nivel === nivel)
      .filter((a) => !soConvocaveis || a.convocado)
      .filter((a) => !termo || a.nome.toLowerCase().includes(termo) || a.cpf.includes(termo.replace(/\D/g, "")))
      .sort((a, b) => b.total - a.total);
  }, [avaliacoes, habilitacao, grupo, nivel, soConvocaveis, busca]);

  if (!avaliacoes.length) return <div className="empty">Nenhuma inscrição enviada até o momento.</div>;

  return (
    <div>
      <div className="painel-toolbar">
        <div className="painel-tabs">
          {(["todos", "habilitados", "inabilitados"] as const).map((f) => (
            <button key={f} type="button" className={`btn btn-sm${habilitacao === f ? " btn-primary" : ""}`} onClick={() => setHabilitacao(f)}>
              {f === "todos" ? `Todos (${avaliacoes.length})` : f === "habilitados" ? `Habilitados (${avaliacoes.filter((a) => a.habilitado).length})` : `Inabilitados (${avaliacoes.filter((a) => !a.habilitado).length})`}
            </button>
          ))}
        </div>
        <input className="painel-busca" placeholder="Buscar por nome ou CPF…" value={busca} onChange={(e) => setBusca(e.target.value)} aria-label="Buscar candidato" />
      </div>

      <div className="filtros-avancados" style={{ marginBottom: 16 }}>
        <select value={grupo} onChange={(e) => setGrupo(e.target.value as Grupo | "todos")} aria-label="Filtrar por grupo">
          <option value="todos">Todos os grupos</option>
          {(Object.keys(GRUPOS) as Grupo[]).map((g) => (
            <option key={g} value={g}>
              {GRUPOS[g].nome}
            </option>
          ))}
        </select>
        <select value={nivel} onChange={(e) => setNivel(e.target.value as Nivel | "todos")} aria-label="Filtrar por nível">
          <option value="todos">Todos os níveis</option>
          {(Object.keys(NIVEIS) as Nivel[]).map((n) => (
            <option key={n} value={n}>
              {NIVEIS[n].nome}
            </option>
          ))}
        </select>
        <label className="check" style={{ marginTop: 0 }}>
          <input type="checkbox" checked={soConvocaveis} onChange={(e) => setSoConvocaveis(e.target.checked)} />
          Só convocados (até 3 por vaga, itens 6.4.4 e 6.5.1)
        </label>
        {(grupo !== "todos" || nivel !== "todos" || soConvocaveis || busca) ? (
          <button
            type="button"
            className="btn btn-sm btn-ghost"
            onClick={() => {
              setGrupo("todos");
              setNivel("todos");
              setSoConvocaveis(false);
              setBusca("");
            }}
          >
            Limpar filtros
          </button>
        ) : null}
      </div>

      {linhas.length === 0 ? (
        <div className="empty">Nenhum candidato encontrado com esses filtros.</div>
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
                <th>Convocação</th>
              </tr>
            </thead>
            <tbody>
              {linhas.map((a) => (
                <tr key={a.inscricao_id} onClick={() => router.push(`/painel/candidato/${a.inscricao_id}?aba=analise`)} tabIndex={0}>
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
                  <td>
                    {a.convocado ? (
                      <div style={{ display: "grid", gap: 6, justifyItems: "start" }}>
                        <span className="pill pill-ok">Convocado{a.posicao ? ` (${a.posicao}º)` : ""}</span>
                        {convites[a.inscricao_id] ? (
                          <small className="hint">
                            Convite: {fmtDia(convites[a.inscricao_id].data)} às {convites[a.inscricao_id].horario}
                            {convites[a.inscricao_id].email_enviado ? "" : " (e-mail não enviado)"}
                          </small>
                        ) : null}
                        <ConviteEntrevista
                          inscricaoId={a.inscricao_id}
                          nome={a.nome}
                          grupo={a.grupo}
                          nivel={a.nivel}
                          jaConvidado={Boolean(convites[a.inscricao_id])}
                          aoEnviar={() => setVersaoConvites((v) => v + 1)}
                          pequeno
                        />
                      </div>
                    ) : a.posicao ? (
                      <span className="pill pill-muted">
                        {a.posicao}º, fora do corte ({a.vagas} vaga{a.vagas === 1 ? "" : "s"} × 3)
                      </span>
                    ) : a.habilitado ? (
                      <span className="pill pill-muted">Abaixo de 35 pts</span>
                    ) : null}
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
