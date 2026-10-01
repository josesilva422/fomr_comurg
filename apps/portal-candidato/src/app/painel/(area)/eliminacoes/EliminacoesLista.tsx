"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import type { Grupo, Nivel } from "@/lib/tipos";

interface Eliminacao {
  id: string;
  inscricao_id: string;
  nome: string;
  cpf: string;
  status_anterior: string;
  motivo: string;
  decidido_em: string;
  decidido_por: string;
  revertido_em: string | null;
  revertido_por: string | null;
  motivo_reversao: string | null;
}

interface Candidato {
  inscricao_id: string;
  nome: string;
  cpf: string;
  grupo: Grupo | null;
  nivel: Nivel | null;
  status: string;
}

const fmtCPF = (v: string) => v.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4");
const fmtData = (v: string | null) => (v ? new Date(v).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" }) : "—");

export function EliminacoesLista() {
  const [linhas, setLinhas] = useState<Eliminacao[] | null>(null);
  const [erro, setErro] = useState("");
  const [versao, setVersao] = useState(0);
  const [eliminando, setEliminando] = useState(false);
  const [filtro, setFiltro] = useState<"ativas" | "revertidas" | "todas">("ativas");

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("listar_eliminacoes")
      .then(({ data, error }: { data: Eliminacao[] | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else {
          setErro("");
          setLinhas(data ?? []);
        }
      });
  }, [versao]);

  const cont = linhas
    ? { ativas: linhas.filter((l) => !l.revertido_em).length, revertidas: linhas.filter((l) => l.revertido_em).length, todas: linhas.length }
    : { ativas: 0, revertidas: 0, todas: 0 };
  const visiveis = (linhas ?? []).filter((l) => (filtro === "todas" ? true : filtro === "ativas" ? !l.revertido_em : Boolean(l.revertido_em)));

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: 12, marginBottom: 12 }}>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          {(
            [
              ["ativas", "Ativas"],
              ["revertidas", "Revertidas"],
              ["todas", "Todas"],
            ] as [typeof filtro, string][]
          ).map(([f, rotulo]) => (
            <button key={f} type="button" className={`btn btn-sm${filtro === f ? " btn-primary" : " btn-ghost"}`} onClick={() => setFiltro(f)}>
              {rotulo} ({cont[f]})
            </button>
          ))}
        </div>
        <button type="button" className="btn btn-primary" onClick={() => setEliminando(true)}>
          Eliminar por fraude ou falsidade
        </button>
      </div>

      {eliminando ? (
        <Eliminar
          onFechar={() => setEliminando(false)}
          onEliminado={() => {
            setEliminando(false);
            setVersao((v) => v + 1);
          }}
        />
      ) : null}

      {erro ? <p className="err">{erro}</p> : null}
      {!linhas ? (
        <p className="hint">Carregando…</p>
      ) : visiveis.length === 0 ? (
        <div className="empty">Nenhuma eliminação neste filtro.</div>
      ) : (
        <div className="tabela-wrap">
          <table className="tabela">
            <thead>
              <tr>
                <th>Candidato</th>
                <th>Motivo</th>
                <th>Decidido em</th>
                <th>Situação</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {visiveis.map((l) => (
                <LinhaEliminacao key={l.id} l={l} recarregar={() => setVersao((v) => v + 1)} />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function LinhaEliminacao({ l, recarregar }: { l: Eliminacao; recarregar: () => void }) {
  const [aberta, setAberta] = useState(false);
  const [motivo, setMotivo] = useState("");
  const [erro, setErro] = useState("");
  const [salvando, setSalvando] = useState(false);

  async function reverter() {
    setErro("");
    if (motivo.trim().length < 10) return setErro("Informe o motivo da reversão (mínimo de 10 caracteres).");
    setSalvando(true);
    const { error } = await createClient().schema("painel").rpc("reverter_eliminacao", { p_inscricao_id: l.inscricao_id, p_motivo: motivo.trim() });
    setSalvando(false);
    if (error) return setErro(error.message);
    recarregar();
  }

  return (
    <>
      <tr>
        <td>
          <strong>{l.nome}</strong>
          <div>
            <small className="hint">{fmtCPF(l.cpf)}</small>
          </div>
        </td>
        <td style={{ maxWidth: 360 }}>{l.motivo}</td>
        <td>
          {fmtData(l.decidido_em)}
          <div>
            <small className="hint">por {l.decidido_por}</small>
          </div>
        </td>
        <td>
          {l.revertido_em ? (
            <span className="pill pill-muted">Revertida em {fmtData(l.revertido_em)}</span>
          ) : (
            <span className="pill pill-err">Eliminada (status anterior: {l.status_anterior})</span>
          )}
        </td>
        <td style={{ textAlign: "right" }}>
          {!l.revertido_em ? (
            <button type="button" className="btn btn-sm" onClick={() => setAberta(!aberta)}>
              {aberta ? "Fechar" : "Reverter"}
            </button>
          ) : null}
        </td>
      </tr>
      {aberta ? (
        <tr>
          <td colSpan={5}>
            <div style={{ display: "grid", gap: 12, padding: "8px 0" }}>
              <div className="field">
                <label htmlFor={`motivo-reversao-${l.id}`}>Motivo da reversão — obrigatório</label>
                <textarea
                  id={`motivo-reversao-${l.id}`}
                  rows={2}
                  value={motivo}
                  onChange={(e) => setMotivo(e.target.value)}
                  placeholder="Ex.: Nova apuração afastou o indício de fraude."
                />
              </div>
              {erro ? (
                <p className="err" role="alert">
                  {erro}
                </p>
              ) : null}
              <div>
                <button type="button" className="btn btn-primary" disabled={salvando} onClick={() => void reverter()}>
                  Confirmar reversão (volta a {l.status_anterior})
                </button>
              </div>
            </div>
          </td>
        </tr>
      ) : null}
    </>
  );
}

function Eliminar({ onFechar, onEliminado }: { onFechar: () => void; onEliminado: () => void }) {
  const [busca, setBusca] = useState("");
  const [opcoes, setOpcoes] = useState<Candidato[]>([]);
  const [buscando, setBuscando] = useState(false);
  const [escolhido, setEscolhido] = useState<Candidato | null>(null);
  const [motivo, setMotivo] = useState("");
  const [erro, setErro] = useState("");
  const [salvando, setSalvando] = useState(false);

  useEffect(() => {
    if (escolhido || busca.trim().length < 3) {
      setOpcoes([]);
      return;
    }
    setBuscando(true);
    const t = setTimeout(() => {
      createClient()
        .schema("painel")
        .rpc("buscar_inscricao", { p_busca: busca.trim() })
        .then(({ data }: { data: Candidato[] | null }) => {
          setOpcoes(data ?? []);
          setBuscando(false);
        });
    }, 300);
    return () => clearTimeout(t);
  }, [busca, escolhido]);

  async function eliminar() {
    setErro("");
    if (!escolhido) return setErro("Escolha o candidato.");
    if (motivo.trim().length < 20) return setErro("Justifique com o indício constatado (mínimo de 20 caracteres, itens 5.5.4 e 14.3).");
    setSalvando(true);
    const { error } = await createClient().schema("painel").rpc("eliminar_por_fraude", { p_inscricao_id: escolhido.inscricao_id, p_motivo: motivo.trim() });
    setSalvando(false);
    if (error) return setErro(error.message);
    onEliminado();
  }

  return (
    <div className="card" style={{ marginBottom: 16, border: "1px solid var(--border)" }}>
      <div style={{ display: "grid", gap: 12 }}>
        {!escolhido ? (
          <div className="field">
            <label htmlFor="busca-elim">Candidato (nome ou CPF)</label>
            <input id="busca-elim" value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Digite ao menos 3 caracteres…" />
            {buscando ? <small className="hint">Buscando…</small> : null}
            {opcoes.length > 0 ? (
              <ul className="pend" style={{ marginTop: 6 }}>
                {opcoes.map((o) => (
                  <li key={o.inscricao_id}>
                    <span>
                      {o.nome} — {fmtCPF(o.cpf)}
                      {o.grupo && o.nivel ? ` · ${GRUPOS[o.grupo].nome} · ${NIVEIS[o.nivel].nome}` : ""} · {o.status}
                    </span>
                    <button type="button" className="btn btn-sm" onClick={() => setEscolhido(o)}>
                      Escolher
                    </button>
                  </li>
                ))}
              </ul>
            ) : null}
          </div>
        ) : (
          <div className="alert alert-err" style={{ margin: 0 }}>
            <p style={{ margin: 0 }}>
              <b>{escolhido.nome}</b> — {fmtCPF(escolhido.cpf)} ({escolhido.status}){" "}
              <button type="button" className="btn btn-sm" style={{ marginLeft: 8 }} onClick={() => setEscolhido(null)}>
                Trocar
              </button>
            </p>
          </div>
        )}

        <div className="field">
          <label htmlFor="motivo-elim">Indício de fraude ou falsidade constatado</label>
          <textarea
            id="motivo-elim"
            rows={4}
            value={motivo}
            onChange={(e) => setMotivo(e.target.value)}
            placeholder="Descreva o documento e a irregularidade apurada (ex.: diploma com instituição inexistente no e-MEC, confirmado por consulta oficial em DD/MM/AAAA)."
          />
        </div>

        {erro ? (
          <p className="err" role="alert">
            {erro}
          </p>
        ) : null}

        <div style={{ display: "flex", gap: 8 }}>
          <button type="button" className="btn btn-primary" disabled={salvando} onClick={() => void eliminar()}>
            Eliminar inscrição
          </button>
          <button type="button" className="btn btn-ghost" onClick={onFechar}>
            Cancelar
          </button>
        </div>
      </div>
    </div>
  );
}
