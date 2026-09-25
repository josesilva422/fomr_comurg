"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

interface LinhaIsencao {
  inscricao_id: string;
  nome: string;
  cpf: string;
  grupo: string | null;
  nivel: string | null;
  status: string;
  submetida_em: string | null;
  hipotese_isencao: "cadunico" | "doador_sangue" | "doador_medula" | null;
  nis_isencao: string | null;
  qtd_documentos: number;
  decisao: Decisao | null;
  motivo: string | null;
  decidido_em: string | null;
  comprovante_enviado: boolean;
  prazo_pagamento: string;
}

interface DocIsencao {
  id: string;
  tipo: string;
  nome_original: string;
  storage_path: string;
}

const HIPOTESE: Record<string, string> = {
  cadunico: "Baixa renda (CadÚnico)",
  doador_sangue: "Doador de sangue",
  doador_medula: "Doador de medula óssea",
};

// O que o decreto pede em cada hipótese (art. 1º, 3º e 4º) — lembrete para a conferência.
const CONFERIR: Record<string, string> = {
  cadunico: "Renda familiar de até 3 salários mínimos ou per capita de até meio salário mínimo, inscrição no CadÚnico (NIS informado) e declaração formal.",
  doador_sangue:
    "Mínimo de 3 doações nos 363 dias anteriores à abertura das inscrições (28/09/2026), com número e data em cada comprovante. Doação de plaquetas não vale.",
  doador_medula:
    "Mínimo de 1 doação nos 365 dias anteriores à abertura das inscrições (28/09/2026): comprovante da unidade coletora, assinado, e inscrição no REDOME.",
};

type Decisao = "deferida" | "indeferida" | "desconsiderada" | "pagamento_confirmado" | "pagamento_recusado";
const ROTULO_DECISAO: Record<Decisao, string> = {
  deferida: "Deferida",
  indeferida: "Indeferida",
  desconsiderada: "Inscrição desconsiderada",
  pagamento_confirmado: "Indeferida · pagamento confirmado",
  pagamento_recusado: "Indeferida · comprovante recusado",
};
const PILL_DECISAO: Record<Decisao, string> = {
  deferida: "pill-ok",
  indeferida: "pill-err",
  desconsiderada: "pill-err",
  pagamento_confirmado: "pill-ok",
  pagamento_recusado: "pill-err",
};
/** Isenção indeferida (ou comprovante recusado) com comprovante novo esperando a Comissão conferir. */
const aConferir = (l: LinhaIsencao) =>
  l.status === "aguardando_isencao" && (l.decisao === "indeferida" || l.decisao === "pagamento_recusado") && l.comprovante_enviado;
const fmtCPF = (v: string) => v.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4");
const fmtData = (v: string | null) => (v ? new Date(v).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" }) : "—");

export function IsencoesLista() {
  const [linhas, setLinhas] = useState<LinhaIsencao[] | null>(null);
  const [erro, setErro] = useState("");
  const [versao, setVersao] = useState(0);
  const [aberta, setAberta] = useState<string | null>(null);

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("listar_isencoes")
      .then(({ data, error }: { data: LinhaIsencao[] | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else {
          setErro("");
          setLinhas(data ?? []);
        }
      });
  }, [versao]);

  if (erro) return <p className="err">{erro}</p>;
  if (!linhas) return <p className="hint">Carregando…</p>;
  if (!linhas.length) return <div className="empty">Nenhum pedido de isenção enviado até o momento.</div>;

  const pendentes = linhas.filter((l) => !l.decisao).length;
  const conferir = linhas.filter(aConferir).length;

  return (
    <div>
      <p className="hint" style={{ marginTop: 0 }}>
        {linhas.length} pedido(s) · <b>{pendentes}</b> aguardando decisão · <b>{conferir}</b> comprovante(s) de Pix a conferir.
      </p>
      <div className="tabela-wrap">
        <table className="tabela">
          <thead>
            <tr>
              <th>Candidato</th>
              <th>Vaga</th>
              <th>Hipótese</th>
              <th>Documentos</th>
              <th>Decisão</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {linhas.map((l) => (
              <LinhaPedido key={l.inscricao_id} l={l} aberta={aberta === l.inscricao_id} alternar={() => setAberta(aberta === l.inscricao_id ? null : l.inscricao_id)} recarregar={() => setVersao((v) => v + 1)} />
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function LinhaPedido({ l, aberta, alternar, recarregar }: { l: LinhaIsencao; aberta: boolean; alternar: () => void; recarregar: () => void }) {
  return (
    <>
      <tr>
        <td>
          <strong>{l.nome}</strong>
          <div>
            <small className="hint">{fmtCPF(l.cpf)}</small>
          </div>
        </td>
        <td>{l.grupo && l.nivel ? `${l.grupo} · ${l.nivel}` : "—"}</td>
        <td>{l.hipotese_isencao ? HIPOTESE[l.hipotese_isencao] : "—"}</td>
        <td>{l.qtd_documentos}</td>
        <td>
          {l.decisao ? (
            <span className={`pill ${PILL_DECISAO[l.decisao]}`}>{ROTULO_DECISAO[l.decisao]}</span>
          ) : (
            <span className="pill pill-muted">Aguardando</span>
          )}
          {aConferir(l) ? (
            <div className="hint">
              <b>Comprovante de Pix a conferir</b>
            </div>
          ) : l.decisao === "indeferida" || l.decisao === "pagamento_recusado" ? (
            <div className="hint">Sem comprovante de Pix novo</div>
          ) : null}
        </td>
        <td style={{ textAlign: "right" }}>
          <button type="button" className="btn btn-sm" onClick={alternar}>
            {aberta ? "Fechar" : !l.decisao ? "Analisar" : aConferir(l) ? "Conferir Pix" : "Ver"}
          </button>
        </td>
      </tr>
      {aberta ? (
        <tr>
          <td colSpan={6}>
            <PainelDecisao l={l} aoDecidir={recarregar} />
          </td>
        </tr>
      ) : null}
    </>
  );
}

function PainelDecisao({ l, aoDecidir }: { l: LinhaIsencao; aoDecidir: () => void }) {
  const [docs, setDocs] = useState<DocIsencao[] | null>(null);
  const [motivo, setMotivo] = useState("");
  const [erro, setErro] = useState("");
  const [salvando, setSalvando] = useState(false);
  const [agora] = useState(() => Date.now());
  const prazoTerminou = agora > new Date(l.prazo_pagamento).getTime();

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("documentos_da_inscricao", { p_inscricao_id: l.inscricao_id })
      .then(({ data, error }: { data: DocIsencao[] | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else setDocs((data ?? []).filter((d) => d.tipo === "requerimento_isencao" || d.tipo === "comprovante_pix"));
      });
  }, [l.inscricao_id]);

  async function ver(d: DocIsencao) {
    setErro("");
    const { data, error } = await createClient().storage.from("documentos").createSignedUrl(d.storage_path, 300);
    if (error) return setErro(error.message);
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }

  async function decidirPagamento(confirmar: boolean) {
    setErro("");
    if (motivo.trim().length < 10) return setErro("Informe o motivo da decisão (mínimo de 10 caracteres).");
    setSalvando(true);
    const { error } = await createClient()
      .schema("painel")
      .rpc("decidir_pagamento_isencao", { p_inscricao_id: l.inscricao_id, p_confirmar: confirmar, p_motivo: motivo });
    setSalvando(false);
    if (error) return setErro(error.message);
    setMotivo("");
    aoDecidir();
  }

  async function decidir(decisao: "deferida" | "indeferida" | "desconsiderada") {
    setErro("");
    if (motivo.trim().length < 10) return setErro("Informe o motivo da decisão (mínimo de 10 caracteres).");
    setSalvando(true);
    const { error } = await createClient().schema("painel").rpc("decidir_isencao", { p_inscricao_id: l.inscricao_id, p_decisao: decisao, p_motivo: motivo });
    setSalvando(false);
    if (error) return setErro(error.message);
    setMotivo("");
    aoDecidir();
  }

  return (
    <div style={{ display: "grid", gap: 12, padding: "8px 0" }}>
      <div className="alert alert-ok" style={{ margin: 0 }}>
        <p>
          <b>Hipótese declarada:</b> {l.hipotese_isencao ? HIPOTESE[l.hipotese_isencao] : "não informada"}
          {l.hipotese_isencao === "cadunico" ? ` · NIS ${l.nis_isencao ?? "(não informado)"}` : ""}
        </p>
        {l.hipotese_isencao ? (
          <p>
            <b>Conferir:</b> {CONFERIR[l.hipotese_isencao]}
          </p>
        ) : null}
      </div>

      <div>
        <strong>Documentos anexados</strong>
        {!docs ? (
          <p className="hint">Carregando…</p>
        ) : docs.length === 0 ? (
          <p className="hint">Nenhum documento anexado.</p>
        ) : (
          <ul style={{ margin: "6px 0", paddingLeft: 18 }}>
            {docs.map((d) => (
              <li key={d.id}>
                {d.tipo === "comprovante_pix" ? <b>Comprovante do Pix: </b> : null}
                {d.nome_original}{" "}
                <button type="button" className="btn btn-sm btn-ghost" onClick={() => ver(d)}>
                  Abrir
                </button>
              </li>
            ))}
          </ul>
        )}
        <p className="hint" style={{ margin: 0 }}>
          Pedido enviado em {fmtData(l.submetida_em)}.
        </p>
      </div>

      {l.decisao ? (
        <div className="alert" style={{ margin: 0 }}>
          <p>
            <b>Última decisão: {ROTULO_DECISAO[l.decisao].toLowerCase()}</b> em {fmtData(l.decidido_em)}.
          </p>
          <p>Motivo: {l.motivo}</p>
        </div>
      ) : null}

      {l.decisao === "pagamento_confirmado" ? (
        <div className="alert alert-ok" style={{ margin: 0 }}>
          <p>
            Pagamento confirmado: a inscrição segue o fluxo normal, como a de quem pagou a taxa na inscrição. Não há mais decisão de isenção a
            tomar.
          </p>
        </div>
      ) : aConferir(l) ? (
        <>
          <div className="alert alert-warn" style={{ margin: 0 }}>
            <p>
              <b>Conferência do comprovante do Pix</b> (isenção indeferida). Confira: nome e CPF do pagador iguais aos do candidato (item 4.9.1 e
              4.9.4); valor de R$ 100,00; data e hora até {fmtData(l.prazo_pagamento)} (item 4.10.2); chave Pix da COMURG; código E2E. Confirmado, a
              inscrição segue o fluxo normal. Recusado, o candidato vê o motivo e pode enviar outro comprovante até o prazo.
            </p>
          </div>
          <div className="field">
            <label htmlFor={`motivo-${l.inscricao_id}`}>Motivo da decisão (obrigatório)</label>
            <textarea
              id={`motivo-${l.inscricao_id}`}
              rows={3}
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              placeholder="Ex.: Comprovante conferido — nome, CPF, valor, data e E2E conferem."
            />
          </div>
          {erro ? (
            <p className="err" role="alert">
              {erro}
            </p>
          ) : null}
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button type="button" className="btn btn-primary" disabled={salvando} onClick={() => decidirPagamento(true)}>
              Confirmar pagamento (seguir fluxo normal)
            </button>
            <button type="button" className="btn" disabled={salvando} onClick={() => decidirPagamento(false)}>
              Recusar comprovante
            </button>
          </div>
        </>
      ) : (
        <>
          <div className="field">
            <label htmlFor={`motivo-${l.inscricao_id}`}>{l.decisao ? "Nova decisão (ex.: após recurso) — motivo" : "Motivo da decisão"} (obrigatório)</label>
            <textarea id={`motivo-${l.inscricao_id}`} rows={3} value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Fundamente a decisão com base no decreto e nos documentos." />
          </div>
          {erro ? (
            <p className="err" role="alert">
              {erro}
            </p>
          ) : null}
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            {l.decisao !== "desconsiderada" ? (
              <>
                <button type="button" className="btn btn-primary" disabled={salvando} onClick={() => decidir("deferida")}>
                  Deferir isenção
                </button>
                <button type="button" className="btn" disabled={salvando} onClick={() => decidir("indeferida")}>
                  Indeferir isenção
                </button>
              </>
            ) : null}
            {(l.decisao === "indeferida" || l.decisao === "pagamento_recusado") && prazoTerminou ? (
              <button type="button" className="btn" disabled={salvando} onClick={() => decidir("desconsiderada")}>
                Desconsiderar inscrição (sem pagamento no prazo)
              </button>
            ) : null}
          </div>
          <p className="hint" style={{ margin: 0 }}>
            Indeferida: o candidato pode pagar a taxa até {fmtData(l.prazo_pagamento)} (item 4.10.2) e anexar o comprovante no portal; quando ele
            enviar, aparece aqui a conferência do Pix. Depois desse prazo, sem pagamento válido, a Comissão pode desconsiderar a inscrição, com motivo.
            Toda decisão fica registrada na auditoria e o candidato a vê no portal.
          </p>
        </>
      )}
    </div>
  );
}
