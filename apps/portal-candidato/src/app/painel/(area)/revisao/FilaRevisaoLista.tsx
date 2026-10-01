"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import type { Grupo, Nivel } from "@/lib/tipos";

interface Linha {
  documento_id: string;
  inscricao_id: string;
  nome: string;
  cpf: string;
  grupo: Grupo | null;
  nivel: Nivel | null;
  tipo: string;
  enviado_em: string;
  extracao_id: string | null;
  status: "sem_extracao" | "pendente" | "revisada" | "corrigida";
  confianca: number | null;
  legivel: boolean | null;
  suspeita_adulteracao: boolean | null;
  tipo_bate: boolean | null;
  qtd_nao_confere: number;
  resumo: string | null;
  revisado_em: string | null;
  revisado_por: string | null;
}

const fmtCPF = (v: string) => v.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4");
const fmtData = (v: string | null) => (v ? new Date(v).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" }) : "—");
const rotuloTipo = (t: string) => t.replace(/_/g, " ");

export function FilaRevisaoLista() {
  const [linhas, setLinhas] = useState<Linha[] | null>(null);
  const [erro, setErro] = useState("");
  const [versao, setVersao] = useState(0);
  const [filtro, setFiltro] = useState<"pendente" | "revisada" | "corrigida" | "todas">("pendente");
  const [aberta, setAberta] = useState<string | null>(null);

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("listar_fila_revisao", { p_status: filtro })
      .then(({ data, error }: { data: Linha[] | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else {
          setErro("");
          setLinhas(data ?? []);
        }
      });
  }, [filtro, versao]);

  if (erro) return <p className="err">{erro}</p>;

  return (
    <div>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 12 }}>
        {(
          [
            ["pendente", "Pendentes (inclui nunca extraídos)"],
            ["revisada", "Revisadas"],
            ["corrigida", "Corrigidas"],
            ["todas", "Todas"],
          ] as [typeof filtro, string][]
        ).map(([f, rotulo]) => (
          <button key={f} type="button" className={`btn btn-sm${filtro === f ? " btn-primary" : " btn-ghost"}`} onClick={() => setFiltro(f)}>
            {rotulo}
          </button>
        ))}
      </div>

      {!linhas ? (
        <p className="hint">Carregando…</p>
      ) : linhas.length === 0 ? (
        <div className="empty">Nenhum documento neste filtro.</div>
      ) : (
        <div className="tabela-wrap">
          <table className="tabela">
            <thead>
              <tr>
                <th>Candidato</th>
                <th>Documento</th>
                <th>Situação</th>
                <th style={{ textAlign: "right" }}>Confiança</th>
                <th>Indícios</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {linhas.map((l) => (
                <LinhaFila
                  key={l.documento_id}
                  l={l}
                  aberta={aberta === l.documento_id}
                  alternar={() => setAberta(aberta === l.documento_id ? null : l.documento_id)}
                  recarregar={() => setVersao((v) => v + 1)}
                />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function LinhaFila({ l, aberta, alternar, recarregar }: { l: Linha; aberta: boolean; alternar: () => void; recarregar: () => void }) {
  const indicios = l.suspeita_adulteracao || l.legivel === false || l.tipo_bate === false || l.qtd_nao_confere > 0;
  return (
    <>
      <tr>
        <td>
          <strong>{l.nome}</strong>
          <div>
            <small className="hint">
              {fmtCPF(l.cpf)}
              {l.grupo && l.nivel ? ` · ${GRUPOS[l.grupo].nome} · ${NIVEIS[l.nivel].nome}` : ""}
            </small>
          </div>
        </td>
        <td style={{ textTransform: "capitalize" }}>{rotuloTipo(l.tipo)}</td>
        <td>
          {l.status === "sem_extracao" ? (
            <span className="pill pill-muted">Nunca extraído</span>
          ) : l.status === "pendente" ? (
            <span className="pill pill-err">Pendente</span>
          ) : l.status === "revisada" ? (
            <span className="pill pill-ok">Revisada</span>
          ) : (
            <span className="pill pill-ok">Corrigida</span>
          )}
        </td>
        <td style={{ textAlign: "right" }}>{l.confianca !== null ? `${Math.round(l.confianca * 100)}%` : "—"}</td>
        <td>
          {l.suspeita_adulteracao ? <span className="pill pill-err">Suspeita de adulteração</span> : null}
          {l.legivel === false ? <span className="pill pill-err">Ilegível</span> : null}
          {l.tipo_bate === false ? <span className="pill pill-err">Tipo não confere</span> : null}
          {l.qtd_nao_confere > 0 ? <span className="pill pill-err">{l.qtd_nao_confere} campo(s) não confere(m)</span> : null}
          {!indicios && l.status !== "sem_extracao" ? <span className="pill pill-muted">Nenhum</span> : null}
        </td>
        <td style={{ textAlign: "right" }}>
          <button type="button" className="btn btn-sm" onClick={alternar}>
            {aberta ? "Fechar" : "Ver"}
          </button>
        </td>
      </tr>
      {aberta ? (
        <tr>
          <td colSpan={6}>
            <Detalhe l={l} aoRevisar={recarregar} />
          </td>
        </tr>
      ) : null}
    </>
  );
}

function Detalhe({ l, aoRevisar }: { l: Linha; aoRevisar: () => void }) {
  const [observacao, setObservacao] = useState("");
  const [erro, setErro] = useState("");
  const [salvando, setSalvando] = useState<"revisada" | "corrigida" | null>(null);

  async function marcar(status: "revisada" | "corrigida") {
    setErro("");
    if (!l.extracao_id) return setErro("Este documento ainda não foi extraído pela IA.");
    setSalvando(status);
    const { error } = await createClient()
      .schema("painel")
      .rpc("revisar_extracao", { p_extracao_id: l.extracao_id, p_status: status, p_observacao: observacao.trim() || null });
    setSalvando(null);
    if (error) return setErro(error.message);
    setObservacao("");
    aoRevisar();
  }

  return (
    <div style={{ display: "grid", gap: 12, padding: "8px 0" }}>
      <p style={{ margin: 0 }}>
        Enviado em {fmtData(l.enviado_em)} · <Link href={`/painel/candidato/${l.inscricao_id}?aba=documentos`}>Abrir candidato (comparação completa)</Link>
      </p>

      {l.status === "sem_extracao" ? (
        <div className="alert alert-warn" style={{ margin: 0 }}>
          <p style={{ margin: 0 }}>Este documento ainda não foi extraído pela IA. Abra o candidato e use &quot;Verificar com IA&quot; nesse documento.</p>
        </div>
      ) : (
        <>
          {l.resumo ? (
            <div className="alert" style={{ margin: 0 }}>
              <p style={{ margin: 0 }}>{l.resumo}</p>
            </div>
          ) : null}
          {l.revisado_em ? (
            <p className="hint" style={{ margin: 0 }}>
              Já marcado como {l.status} em {fmtData(l.revisado_em)} por {l.revisado_por}.
            </p>
          ) : null}

          <div className="field">
            <label htmlFor={`obs-${l.documento_id}`}>Observação (opcional)</label>
            <textarea
              id={`obs-${l.documento_id}`}
              rows={2}
              value={observacao}
              onChange={(e) => setObservacao(e.target.value)}
              placeholder="Ex.: a IA leu o CPF errado; confirmado manualmente que o documento está correto."
            />
          </div>
          {erro ? (
            <p className="err" role="alert">
              {erro}
            </p>
          ) : null}
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button type="button" className="btn btn-primary" disabled={salvando !== null} onClick={() => void marcar("revisada")}>
              Marcar como revisada (confere)
            </button>
            <button type="button" className="btn" disabled={salvando !== null} onClick={() => void marcar("corrigida")}>
              Marcar como corrigida (a IA errou)
            </button>
          </div>
        </>
      )}
    </div>
  );
}
