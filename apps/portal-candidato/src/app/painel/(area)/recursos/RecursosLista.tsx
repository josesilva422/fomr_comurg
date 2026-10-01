"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import type { Grupo, Nivel } from "@/lib/tipos";

type Etapa = "isencao" | "inscricao" | "ac" | "entrevista" | "reservas_vagas" | "resultado_final";

const ETAPAS: Record<Etapa, string> = {
  isencao: "Indeferimento de isenção (9.1.a)",
  inscricao: "Indeferimento de inscrição (9.1.b)",
  ac: "Resultado preliminar de habilitação/AC (9.1.c)",
  entrevista: "Resultado preliminar da entrevista (9.1.d)",
  reservas_vagas: "Resultado de reservas de vagas (9.1.e)",
  resultado_final: "Resultado preliminar final (9.1.f)",
};

interface Recurso {
  id: string;
  inscricao_id: string;
  nome: string;
  cpf: string;
  grupo: Grupo | null;
  nivel: Nivel | null;
  etapa: Etapa;
  recebido_em: string;
  fundamentacao: string;
  decisao: "pendente" | "deferido" | "indeferido";
  decisao_motivada: string | null;
  decidido_em: string | null;
  decidido_por: string | null;
  registrado_em: string;
  registrado_por: string;
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
const fmtDia = (v: string) => v.split("-").reverse().join("/");
const fmtData = (v: string | null) => (v ? new Date(v).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" }) : "—");

export function RecursosLista() {
  const [linhas, setLinhas] = useState<Recurso[] | null>(null);
  const [erro, setErro] = useState("");
  const [versao, setVersao] = useState(0);
  const [aberto, setAberto] = useState<string | null>(null);
  const [filtro, setFiltro] = useState<"pendente" | "deferido" | "indeferido" | "todos">("pendente");
  const [registrando, setRegistrando] = useState(false);

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("listar_recursos")
      .then(({ data, error }: { data: Recurso[] | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else {
          setErro("");
          setLinhas(data ?? []);
        }
      });
  }, [versao]);

  const cont = linhas
    ? {
        pendente: linhas.filter((l) => l.decisao === "pendente").length,
        deferido: linhas.filter((l) => l.decisao === "deferido").length,
        indeferido: linhas.filter((l) => l.decisao === "indeferido").length,
        todos: linhas.length,
      }
    : { pendente: 0, deferido: 0, indeferido: 0, todos: 0 };
  const visiveis = (linhas ?? []).filter((l) => (filtro === "todos" ? true : l.decisao === filtro));

  return (
    <div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: 12, marginBottom: 12 }}>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          {(
            [
              ["pendente", "Pendentes"],
              ["deferido", "Deferidos"],
              ["indeferido", "Indeferidos"],
              ["todos", "Todos"],
            ] as [typeof filtro, string][]
          ).map(([f, rotulo]) => (
            <button key={f} type="button" className={`btn btn-sm${filtro === f ? " btn-primary" : " btn-ghost"}`} onClick={() => setFiltro(f)}>
              {rotulo} ({cont[f]})
            </button>
          ))}
        </div>
        <button type="button" className="btn btn-primary" onClick={() => setRegistrando(true)}>
          Registrar recurso recebido
        </button>
      </div>

      {registrando ? (
        <RegistrarRecurso
          onFechar={() => setRegistrando(false)}
          onRegistrado={() => {
            setRegistrando(false);
            setVersao((v) => v + 1);
          }}
        />
      ) : null}

      {erro ? <p className="err">{erro}</p> : null}
      {!linhas ? (
        <p className="hint">Carregando…</p>
      ) : visiveis.length === 0 ? (
        <div className="empty">Nenhum recurso neste filtro.</div>
      ) : (
        <div className="tabela-wrap">
          <table className="tabela">
            <thead>
              <tr>
                <th>Candidato</th>
                <th>Etapa</th>
                <th>Recebido em</th>
                <th>Decisão</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {visiveis.map((l) => (
                <LinhaRecurso
                  key={l.id}
                  l={l}
                  aberta={aberto === l.id}
                  alternar={() => setAberto(aberto === l.id ? null : l.id)}
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

function LinhaRecurso({ l, aberta, alternar, recarregar }: { l: Recurso; aberta: boolean; alternar: () => void; recarregar: () => void }) {
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
        <td>{ETAPAS[l.etapa]}</td>
        <td>{fmtDia(l.recebido_em)}</td>
        <td>
          {l.decisao === "deferido" ? (
            <span className="pill pill-ok">Deferido</span>
          ) : l.decisao === "indeferido" ? (
            <span className="pill pill-err">Indeferido</span>
          ) : (
            <span className="pill pill-muted">Pendente</span>
          )}
        </td>
        <td style={{ textAlign: "right" }}>
          <button type="button" className="btn btn-sm" onClick={alternar}>
            {aberta ? "Fechar" : l.decisao === "pendente" ? "Decidir" : "Ver"}
          </button>
        </td>
      </tr>
      {aberta ? (
        <tr>
          <td colSpan={5}>
            <DecidirRecurso l={l} aoDecidir={recarregar} />
          </td>
        </tr>
      ) : null}
    </>
  );
}

function DecidirRecurso({ l, aoDecidir }: { l: Recurso; aoDecidir: () => void }) {
  const [motivo, setMotivo] = useState("");
  const [erro, setErro] = useState("");
  const [salvando, setSalvando] = useState(false);

  async function decidir(deferido: boolean) {
    setErro("");
    if (motivo.trim().length < 10) return setErro("Informe o motivo da decisão (mínimo de 10 caracteres). É sempre exigido (itens 1.5 e 1.6).");
    setSalvando(true);
    const { error } = await createClient()
      .schema("painel")
      .rpc("decidir_recurso", { p_recurso_id: l.id, p_deferido: deferido, p_motivo: motivo.trim() });
    setSalvando(false);
    if (error) return setErro(error.message);
    setMotivo("");
    aoDecidir();
  }

  return (
    <div style={{ display: "grid", gap: 12, padding: "8px 0" }}>
      <p style={{ margin: 0 }}>
        Recebido em {fmtDia(l.recebido_em)} · registrado por {l.registrado_por} em {fmtData(l.registrado_em)}
      </p>
      <div className="alert" style={{ margin: 0 }}>
        <p style={{ margin: 0 }}>
          <b>Fundamentação do recurso:</b> {l.fundamentacao}
        </p>
      </div>

      {l.decisao !== "pendente" ? (
        <div className="alert" style={{ margin: 0 }}>
          <p>
            <b>Decisão: {l.decisao === "deferido" ? "deferido" : "indeferido"}</b> em {fmtData(l.decidido_em)}
            {l.decidido_por ? ` por ${l.decidido_por}` : ""}.
          </p>
          {l.decisao_motivada ? <p style={{ margin: 0 }}>Motivo: {l.decisao_motivada}</p> : null}
        </div>
      ) : null}

      <div className="field">
        <label htmlFor={`motivo-recurso-${l.id}`}>{l.decisao !== "pendente" ? "Nova decisão" : "Decisão"} — motivo sempre obrigatório</label>
        <textarea
          id={`motivo-recurso-${l.id}`}
          rows={3}
          value={motivo}
          onChange={(e) => setMotivo(e.target.value)}
          placeholder="Ex.: Conferido o comprovante original; o CPF do pagador confere com o do candidato (item 4.9.4)."
        />
      </div>
      {erro ? (
        <p className="err" role="alert">
          {erro}
        </p>
      ) : null}
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        <button type="button" className="btn btn-primary" disabled={salvando} onClick={() => void decidir(true)}>
          Deferir
        </button>
        <button type="button" className="btn" disabled={salvando} onClick={() => void decidir(false)}>
          Indeferir
        </button>
      </div>
      {l.etapa === "inscricao" ? (
        <p className="hint" style={{ margin: 0 }}>
          Se deferido, a inscrição volta a homologada automaticamente e segue o fluxo normal (item 4.13, minuta v11).
        </p>
      ) : null}
    </div>
  );
}

function RegistrarRecurso({ onFechar, onRegistrado }: { onFechar: () => void; onRegistrado: () => void }) {
  const [busca, setBusca] = useState("");
  const [opcoes, setOpcoes] = useState<Candidato[]>([]);
  const [buscando, setBuscando] = useState(false);
  const [escolhido, setEscolhido] = useState<Candidato | null>(null);
  const [etapa, setEtapa] = useState<Etapa>("inscricao");
  const [recebidoEm, setRecebidoEm] = useState(() => new Date().toLocaleDateString("en-CA", { timeZone: "America/Sao_Paulo" }));
  const [fundamentacao, setFundamentacao] = useState("");
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

  async function registrar() {
    setErro("");
    if (!escolhido) return setErro("Escolha o candidato.");
    if (fundamentacao.trim().length < 5) return setErro("Informe a fundamentação do recurso (mínimo de 5 caracteres).");
    setSalvando(true);
    const { error } = await createClient()
      .schema("painel")
      .rpc("registrar_recurso", { p_inscricao_id: escolhido.inscricao_id, p_etapa: etapa, p_recebido_em: recebidoEm, p_fundamentacao: fundamentacao.trim() });
    setSalvando(false);
    if (error) return setErro(error.message);
    onRegistrado();
  }

  return (
    <div className="card" style={{ marginBottom: 16, border: "1px solid var(--border)" }}>
      <div style={{ display: "grid", gap: 12 }}>
        {!escolhido ? (
          <div className="field">
            <label htmlFor="busca-recurso">Candidato (nome ou CPF)</label>
            <input id="busca-recurso" value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Digite ao menos 3 caracteres…" />
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
          <div className="alert" style={{ margin: 0 }}>
            <p style={{ margin: 0 }}>
              <b>{escolhido.nome}</b> — {fmtCPF(escolhido.cpf)}{" "}
              <button type="button" className="btn btn-sm" style={{ marginLeft: 8 }} onClick={() => setEscolhido(null)}>
                Trocar
              </button>
            </p>
          </div>
        )}

        <div className="field">
          <label htmlFor="etapa-recurso">Contra qual decisão (item 9.1)</label>
          <select id="etapa-recurso" value={etapa} onChange={(e) => setEtapa(e.target.value as Etapa)}>
            {Object.entries(ETAPAS).map(([v, rotulo]) => (
              <option key={v} value={v}>
                {rotulo}
              </option>
            ))}
          </select>
        </div>

        <div className="field">
          <label htmlFor="data-recurso">Recebido em (e-mail, item 9.2)</label>
          <input id="data-recurso" type="date" value={recebidoEm} onChange={(e) => setRecebidoEm(e.target.value)} />
        </div>

        <div className="field">
          <label htmlFor="fundamentacao-recurso">Fundamentação do recurso</label>
          <textarea
            id="fundamentacao-recurso"
            rows={3}
            value={fundamentacao}
            onChange={(e) => setFundamentacao(e.target.value)}
            placeholder="Resumo do que o candidato alegou no e-mail."
          />
        </div>

        {erro ? (
          <p className="err" role="alert">
            {erro}
          </p>
        ) : null}

        <div style={{ display: "flex", gap: 8 }}>
          <button type="button" className="btn btn-primary" disabled={salvando} onClick={() => void registrar()}>
            Registrar
          </button>
          <button type="button" className="btn btn-ghost" onClick={onFechar}>
            Cancelar
          </button>
        </div>
      </div>
    </div>
  );
}
