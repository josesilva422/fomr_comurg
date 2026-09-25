"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import type { Grupo, Nivel } from "@/lib/tipos";

interface LinhaHomologacao {
  inscricao_id: string;
  nome: string;
  cpf: string;
  grupo: Grupo | null;
  nivel: Nivel | null;
  status: string;
  submetida_em: string | null;
  pagamento: "pix" | "isencao" | "pix_apos_isencao" | null;
  decisao: "aprovada" | "rejeitada" | null;
  motivo: string | null;
  decidido_em: string | null;
  decidido_por: string | null;
}

interface DocInscricao {
  id: string;
  tipo: string;
  nome_original: string;
  storage_path: string;
}

type Filtro = "pendentes" | "aprovada" | "rejeitada" | "todas";

const PAGAMENTO: Record<string, string> = {
  pix: "Pix na inscrição",
  isencao: "Isenção deferida",
  pix_apos_isencao: "Pix após isenção indeferida (confirmado)",
};
const fmtCPF = (v: string) => v.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4");
const fmtData = (v: string | null) => (v ? new Date(v).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" }) : "—");

// Homologação das inscrições (Anexo IV, item 10): um membro da Comissão aprova ou rejeita cada inscrição enviada.
// Rejeitar exige explicação (item 1.6), que o candidato vê; cabe recurso (item 9.1, alínea b).
export function HomologacaoLista() {
  const [linhas, setLinhas] = useState<LinhaHomologacao[] | null>(null);
  const [erro, setErro] = useState("");
  const [versao, setVersao] = useState(0);
  const [aberta, setAberta] = useState<string | null>(null);
  const [filtro, setFiltro] = useState<Filtro>("pendentes");

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("listar_homologacao")
      .then(({ data, error }: { data: LinhaHomologacao[] | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else {
          setErro("");
          setLinhas(data ?? []);
        }
      });
  }, [versao]);

  if (erro) return <p className="err">{erro}</p>;
  if (!linhas) return <p className="hint">Carregando…</p>;
  if (!linhas.length) return <div className="empty">Nenhuma inscrição pronta para homologação até o momento.</div>;

  const cont = {
    pendentes: linhas.filter((l) => !l.decisao).length,
    aprovada: linhas.filter((l) => l.decisao === "aprovada").length,
    rejeitada: linhas.filter((l) => l.decisao === "rejeitada").length,
    todas: linhas.length,
  };
  const visiveis = linhas.filter((l) => (filtro === "todas" ? true : filtro === "pendentes" ? !l.decisao : l.decisao === filtro));

  return (
    <div>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 12 }}>
        {(
          [
            ["pendentes", "Pendentes"],
            ["aprovada", "Aprovadas"],
            ["rejeitada", "Rejeitadas"],
            ["todas", "Todas"],
          ] as [Filtro, string][]
        ).map(([f, rotulo]) => (
          <button key={f} type="button" className={`btn btn-sm${filtro === f ? " btn-primary" : " btn-ghost"}`} onClick={() => setFiltro(f)}>
            {rotulo} ({cont[f]})
          </button>
        ))}
      </div>
      {visiveis.length === 0 ? (
        <div className="empty">Nenhuma inscrição neste filtro.</div>
      ) : (
        <div className="tabela-wrap">
          <table className="tabela">
            <thead>
              <tr>
                <th>Candidato</th>
                <th>Vaga</th>
                <th>Pagamento</th>
                <th>Situação</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {visiveis.map((l) => (
                <Linha
                  key={l.inscricao_id}
                  l={l}
                  aberta={aberta === l.inscricao_id}
                  alternar={() => setAberta(aberta === l.inscricao_id ? null : l.inscricao_id)}
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

function Linha({ l, aberta, alternar, recarregar }: { l: LinhaHomologacao; aberta: boolean; alternar: () => void; recarregar: () => void }) {
  return (
    <>
      <tr>
        <td>
          <strong>{l.nome}</strong>
          <div>
            <small className="hint">{fmtCPF(l.cpf)}</small>
          </div>
        </td>
        <td>{l.grupo && l.nivel ? `${GRUPOS[l.grupo].nome} · ${NIVEIS[l.nivel].nome}` : "—"}</td>
        <td>{l.pagamento ? PAGAMENTO[l.pagamento] : "—"}</td>
        <td>
          {l.decisao === "aprovada" ? (
            <span className="pill pill-ok">Aprovada</span>
          ) : l.decisao === "rejeitada" ? (
            <span className="pill pill-err">Rejeitada</span>
          ) : (
            <span className="pill pill-muted">Pendente</span>
          )}
        </td>
        <td style={{ textAlign: "right" }}>
          <button type="button" className="btn btn-sm" onClick={alternar}>
            {aberta ? "Fechar" : l.decisao ? "Ver" : "Analisar"}
          </button>
        </td>
      </tr>
      {aberta ? (
        <tr>
          <td colSpan={5}>
            <Decisao l={l} aoDecidir={recarregar} />
          </td>
        </tr>
      ) : null}
    </>
  );
}

function Decisao({ l, aoDecidir }: { l: LinhaHomologacao; aoDecidir: () => void }) {
  const [comprovantes, setComprovantes] = useState<DocInscricao[] | null>(null);
  const [motivo, setMotivo] = useState("");
  const [erro, setErro] = useState("");
  const [salvando, setSalvando] = useState(false);

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("documentos_da_inscricao", { p_inscricao_id: l.inscricao_id })
      .then(({ data, error }: { data: DocInscricao[] | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else setComprovantes((data ?? []).filter((d) => d.tipo === "comprovante_pix"));
      });
  }, [l.inscricao_id]);

  async function abrir(d: DocInscricao) {
    setErro("");
    const { data, error } = await createClient().storage.from("documentos").createSignedUrl(d.storage_path, 300);
    if (error) return setErro(error.message);
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }

  async function decidir(aprovar: boolean) {
    setErro("");
    if (!aprovar && motivo.trim().length < 10) return setErro("Para rejeitar, explique o motivo (mínimo de 10 caracteres). O candidato vai ver esse texto.");
    setSalvando(true);
    const { error } = await createClient()
      .schema("painel")
      .rpc("decidir_inscricao", { p_inscricao_id: l.inscricao_id, p_aprovar: aprovar, p_motivo: motivo.trim() || null });
    setSalvando(false);
    if (error) return setErro(error.message);
    setMotivo("");
    aoDecidir();
  }

  return (
    <div style={{ display: "grid", gap: 12, padding: "8px 0" }}>
      <p style={{ margin: 0 }}>
        Inscrição enviada em {fmtData(l.submetida_em)} · <Link href={`/painel/candidato/${l.inscricao_id}?aba=formulario`}>Abrir formulário e documentos</Link>
      </p>

      {l.pagamento === "pix" ? (
        <div className="alert alert-warn" style={{ margin: 0 }}>
          <p>
            <b>Confira o comprovante do Pix</b> (item 4.9.4): nome e CPF do pagador iguais aos do candidato (Pix de terceiros não é aceito, 4.9.1),
            valor de R$ 100,00, data e hora dentro do período de inscrições (4.9.5), chave Pix da COMURG e código E2E.
          </p>
          {!comprovantes ? (
            <p className="hint">Carregando comprovante…</p>
          ) : comprovantes.length === 0 ? (
            <p>Nenhum comprovante do Pix anexado.</p>
          ) : (
            <p>
              {comprovantes.map((d) => (
                <button key={d.id} type="button" className="btn btn-sm" style={{ marginRight: 6 }} onClick={() => void abrir(d)}>
                  Abrir comprovante ({d.nome_original})
                </button>
              ))}
            </p>
          )}
        </div>
      ) : (
        <p className="hint" style={{ margin: 0 }}>
          {l.pagamento === "isencao" ? "Isenção da taxa deferida pela Comissão." : "Pagamento conferido pela Comissão após o indeferimento da isenção."}
        </p>
      )}

      {l.decisao ? (
        <div className="alert" style={{ margin: 0 }}>
          <p>
            <b>Última decisão: {l.decisao === "aprovada" ? "aprovada" : "rejeitada"}</b> em {fmtData(l.decidido_em)}
            {l.decidido_por ? ` por ${l.decidido_por}` : ""}.
          </p>
          {l.motivo ? <p>Motivo: {l.motivo}</p> : null}
        </div>
      ) : null}

      <div className="field">
        <label htmlFor={`motivo-${l.inscricao_id}`}>
          {l.decisao ? "Nova decisão (ex.: após recurso)" : "Explicação"} — <b>obrigatória para rejeitar</b>; o candidato vê a explicação da rejeição
        </label>
        <textarea
          id={`motivo-${l.inscricao_id}`}
          rows={3}
          value={motivo}
          onChange={(e) => setMotivo(e.target.value)}
          placeholder="Ex.: CPF do pagador do Pix diferente do CPF do candidato (item 4.9.4)."
        />
      </div>
      {erro ? (
        <p className="err" role="alert">
          {erro}
        </p>
      ) : null}
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        <button type="button" className="btn btn-primary" disabled={salvando} onClick={() => decidir(true)}>
          Aprovar inscrição
        </button>
        <button type="button" className="btn" disabled={salvando} onClick={() => decidir(false)}>
          Rejeitar inscrição
        </button>
      </div>
      <p className="hint" style={{ margin: 0 }}>
        Aprovada, o candidato vê &quot;inscrição aprovada&quot;. Rejeitada, ele vê a explicação e pode recorrer (item 9.1, alínea b). A decisão pode ser
        refeita depois (ex.: após recurso) e tudo fica registrado na auditoria.
      </p>
    </div>
  );
}
