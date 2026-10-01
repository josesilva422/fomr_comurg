"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import type { Grupo, Nivel } from "@/lib/tipos";

interface Linha {
  inscricao_id: string;
  nome: string;
  cpf: string;
  grupo: Grupo;
  nivel: Nivel;
  decisao: "confirmada" | "nao_confirmada" | null;
  decisao_motivada: string | null;
  decidido_em: string | null;
  decidido_por: string | null;
}

const fmtCPF = (v: string) => v.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4");
const fmtData = (v: string | null) => (v ? new Date(v).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" }) : "—");

export function HeteroidentificacaoLista() {
  const [linhas, setLinhas] = useState<Linha[] | null>(null);
  const [erro, setErro] = useState("");
  const [versao, setVersao] = useState(0);
  const [aberta, setAberta] = useState<string | null>(null);
  const [filtro, setFiltro] = useState<"pendentes" | "decididos" | "todas">("pendentes");

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("listar_heteroidentificacoes")
      .then(({ data, error }: { data: Linha[] | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else {
          setErro("");
          setLinhas(data ?? []);
        }
      });
  }, [versao]);

  if (erro) return <p className="err">{erro}</p>;
  if (!linhas) return <p className="hint">Carregando…</p>;
  if (!linhas.length) return <div className="empty">Nenhum candidato autodeclarado negro convocado para a entrevista até o momento.</div>;

  const cont = {
    pendentes: linhas.filter((l) => !l.decisao).length,
    decididos: linhas.filter((l) => l.decisao).length,
    todas: linhas.length,
  };
  const visiveis = linhas.filter((l) => (filtro === "todas" ? true : filtro === "pendentes" ? !l.decisao : Boolean(l.decisao)));

  return (
    <div>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 12 }}>
        {(
          [
            ["pendentes", "Pendentes"],
            ["decididos", "Decididos"],
            ["todas", "Todas"],
          ] as [typeof filtro, string][]
        ).map(([f, rotulo]) => (
          <button key={f} type="button" className={`btn btn-sm${filtro === f ? " btn-primary" : " btn-ghost"}`} onClick={() => setFiltro(f)}>
            {rotulo} ({cont[f]})
          </button>
        ))}
      </div>
      {visiveis.length === 0 ? (
        <div className="empty">Nenhum candidato neste filtro.</div>
      ) : (
        <div className="tabela-wrap">
          <table className="tabela">
            <thead>
              <tr>
                <th>Candidato</th>
                <th>Vaga</th>
                <th>Decisão</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {visiveis.map((l) => (
                <Linha key={l.inscricao_id} l={l} aberta={aberta === l.inscricao_id} alternar={() => setAberta(aberta === l.inscricao_id ? null : l.inscricao_id)} recarregar={() => setVersao((v) => v + 1)} />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function Linha({ l, aberta, alternar, recarregar }: { l: Linha; aberta: boolean; alternar: () => void; recarregar: () => void }) {
  return (
    <>
      <tr>
        <td>
          <strong>{l.nome}</strong>
          <div>
            <small className="hint">{fmtCPF(l.cpf)}</small>
          </div>
        </td>
        <td>
          {GRUPOS[l.grupo].nome} · {NIVEIS[l.nivel].nome}
        </td>
        <td>
          {l.decisao === "confirmada" ? (
            <span className="pill pill-ok">Confirmada</span>
          ) : l.decisao === "nao_confirmada" ? (
            <span className="pill pill-err">Não confirmada</span>
          ) : (
            <span className="pill pill-muted">Pendente</span>
          )}
        </td>
        <td style={{ textAlign: "right" }}>
          <button type="button" className="btn btn-sm" onClick={alternar}>
            {aberta ? "Fechar" : l.decisao ? "Ver" : "Decidir"}
          </button>
        </td>
      </tr>
      {aberta ? (
        <tr>
          <td colSpan={4}>
            <Decisao l={l} aoDecidir={recarregar} />
          </td>
        </tr>
      ) : null}
    </>
  );
}

function Decisao({ l, aoDecidir }: { l: Linha; aoDecidir: () => void }) {
  const [motivo, setMotivo] = useState("");
  const [erro, setErro] = useState("");
  const [salvando, setSalvando] = useState(false);

  async function decidir(confirmada: boolean) {
    setErro("");
    if (motivo.trim().length < 10) return setErro("A decisão precisa ser motivada (item 10.4), com pelo menos 10 caracteres.");
    setSalvando(true);
    const { error } = await createClient()
      .schema("painel")
      .rpc("registrar_heteroidentificacao", { p_inscricao_id: l.inscricao_id, p_confirmada: confirmada, p_motivo: motivo.trim() });
    setSalvando(false);
    if (error) return setErro(error.message);
    setMotivo("");
    aoDecidir();
  }

  return (
    <div style={{ display: "grid", gap: 12, padding: "8px 0" }}>
      {l.decisao ? (
        <div className="alert" style={{ margin: 0 }}>
          <p>
            <b>Decisão atual: {l.decisao === "confirmada" ? "confirmada" : "não confirmada"}</b> em {fmtData(l.decidido_em)}
            {l.decidido_por ? ` por ${l.decidido_por}` : ""}.
          </p>
          {l.decisao_motivada ? <p style={{ margin: 0 }}>Motivo: {l.decisao_motivada}</p> : null}
        </div>
      ) : null}

      <div className="field">
        <label htmlFor={`motivo-het-${l.inscricao_id}`}>
          {l.decisao ? "Nova decisão (ex.: recurso à comissão recursal)" : "Decisão"} — motivo sempre obrigatório (item 10.4)
        </label>
        <textarea
          id={`motivo-het-${l.inscricao_id}`}
          rows={3}
          value={motivo}
          onChange={(e) => setMotivo(e.target.value)}
          placeholder="Ex.: Comissão de 5 membros, por videoconferência gravada, confirmou a autodeclaração com base em..."
        />
      </div>
      {erro ? (
        <p className="err" role="alert">
          {erro}
        </p>
      ) : null}
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        <button type="button" className="btn btn-primary" disabled={salvando} onClick={() => void decidir(true)}>
          Confirmar autodeclaração
        </button>
        <button type="button" className="btn" disabled={salvando} onClick={() => void decidir(false)}>
          Não confirmar
        </button>
      </div>
    </div>
  );
}
