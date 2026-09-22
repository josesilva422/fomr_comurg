"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import { ROTULO_DOCUMENTO, type TipoDocumento } from "@/lib/tipos-inscricao";
import { fmtMeses, type AvaliacaoDetalhada, type AvaliacaoResumo } from "@/lib/pontuacao";

interface DocumentoPainel {
  id: string;
  tipo: TipoDocumento;
  nome_original: string;
  storage_path: string;
  mime: string;
  tamanho_bytes: number;
  enviado_em: string;
  extracao: { json_extraido: { campos: Record<string, unknown>; legivel: boolean; confianca_geral: number; observacoes: string | null }; criado_em: string } | null;
}

const fmtCPF = (v: string) => v.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4");
const fmtData = (iso: string | null) => (iso ? new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(iso)) : "—");
const fmtDataCurta = (iso: string) => iso.split("-").reverse().join("/");

export function PainelTabela({ avaliacoes }: { avaliacoes: AvaliacaoResumo[] }) {
  const [aberto, setAberto] = useState<string | null>(null);
  const [filtro, setFiltro] = useState<"todos" | "habilitados" | "inabilitados">("todos");

  if (!avaliacoes.length) return <div className="empty">Nenhuma inscrição enviada até o momento.</div>;

  const filtradas = avaliacoes.filter((a) =>
    filtro === "todos" ? true : filtro === "habilitados" ? a.habilitado : !a.habilitado,
  );

  return (
    <div>
      <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
        {(["todos", "habilitados", "inabilitados"] as const).map((f) => (
          <button key={f} type="button" className={`btn btn-sm${filtro === f ? " btn-primary" : ""}`} onClick={() => setFiltro(f)}>
            {f === "todos" ? `Todos (${avaliacoes.length})` : f === "habilitados" ? `Habilitados (${avaliacoes.filter((a) => a.habilitado).length})` : `Inabilitados (${avaliacoes.filter((a) => !a.habilitado).length})`}
          </button>
        ))}
      </div>
      <div className="repeater">
        {filtradas.map((a) => (
          <Linha key={a.inscricao_id} a={a} aberto={aberto === a.inscricao_id} onToggle={() => setAberto((x) => (x === a.inscricao_id ? null : a.inscricao_id))} />
        ))}
      </div>
    </div>
  );
}

function Linha({ a, aberto, onToggle }: { a: AvaliacaoResumo; aberto: boolean; onToggle: () => void }) {
  return (
    <div className="item">
      <button type="button" onClick={onToggle} style={{ all: "unset", cursor: "pointer", display: "block", width: "100%" }}>
        <div className="item-head" style={{ alignItems: "flex-start", flexWrap: "wrap", gap: 12 }}>
          <div>
            <strong className="item-title">{a.nome}</strong>
            <span className={`badge ${a.habilitado ? "" : "badge-warn"}`} style={a.habilitado ? { background: "var(--ok-bg)", color: "var(--ok-text)", border: "1px solid var(--ok-line)" } : undefined}>
              {a.habilitado ? "Habilitado" : "Inabilitado"}
            </span>
          </div>
          <div style={{ textAlign: "right" }}>
            <div style={{ fontSize: 24, fontWeight: 800, color: "var(--brand)" }}>{a.total.toFixed(1)} pts</div>
            <small className="hint">Formação {a.pontos_formacao.toFixed(1)} · Cursos {a.pontos_cursos.toFixed(1)} · Experiência {a.pontos_experiencia.toFixed(1)}</small>
          </div>
        </div>
        <div className="chips" style={{ marginTop: 8 }}>
          <span className="chip">{fmtCPF(a.cpf)}</span>
          <span className="chip">{GRUPOS[a.grupo].nome} · {NIVEIS[a.nivel].nome}</span>
          <span className="chip">{a.status === "aguardando_isencao" ? "Aguardando isenção" : "Submetida"}</span>
          <span className="chip">Enviada em {fmtData(a.submetida_em)}</span>
        </div>
        {!a.habilitado && a.motivos.length ? (
          <ul style={{ margin: "10px 0 0 18px", fontSize: 14, color: "var(--err)" }}>
            {a.motivos.map((m, i) => (
              <li key={i}>{m.mensagem}</li>
            ))}
          </ul>
        ) : null}
        <p className="link" style={{ marginTop: 10, fontSize: 14 }}>{aberto ? "Ocultar detalhamento ▲" : "Ver detalhamento ▼"}</p>
      </button>
      {aberto ? <Detalhamento inscricaoId={a.inscricao_id} email={a.email} telefone={a.telefone} /> : null}
    </div>
  );
}

function Detalhamento({ inscricaoId, email, telefone }: { inscricaoId: string; email: string; telefone: string }) {
  const [dados, setDados] = useState<AvaliacaoDetalhada | null>(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState("");

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("avaliacao_detalhada", { p_inscricao_id: inscricaoId })
      .then(({ data, error }: { data: AvaliacaoDetalhada | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else setDados(data);
        setCarregando(false);
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (carregando) return <p className="hint" style={{ marginTop: 12 }}>Calculando…</p>;
  if (erro) return <p className="err">{erro}</p>;
  if (!dados) return null;
  const d = dados.detalhamento;

  return (
    <div style={{ marginTop: 16, borderTop: "1px dashed var(--line-strong)", paddingTop: 16 }}>
      <dl className="kv-list">
        <div className="kv">
          <dt>Contato</dt>
          <dd>{email} · {telefone}</dd>
        </div>
      </dl>

      <h4 style={{ marginTop: 4 }}>Formação acadêmica adicional — {d.formacao.total.toFixed(1)} / {d.formacao.teto},0 pts</h4>
      {d.formacao.itens.length === 0 ? (
        <p className="hint">Nenhum título declarado.</p>
      ) : (
        <TabelaItens itens={d.formacao.itens.map((it) => ({ ...it, extra: fmtDataCurta(it.data_conclusao) }))} />
      )}

      <h4 style={{ marginTop: 20 }}>Cursos e certificações — {d.cursos.total.toFixed(1)} / {d.cursos.teto},0 pts</h4>
      {d.cursos.itens.length === 0 ? (
        <p className="hint">Nenhum curso ou certificação declarado.</p>
      ) : (
        <TabelaItens
          itens={d.cursos.itens.map((it) => ({
            ...it,
            extra: `${it.carga_horaria ? it.carga_horaria + "h · " : ""}${fmtDataCurta(it.data_conclusao)}${it.no_catalogo_do_grupo ? "" : " · fora do catálogo"}`,
          }))}
        />
      )}

      <h4 style={{ marginTop: 20 }}>Experiência específica — {d.experiencia.pontos.toFixed(1)} / {d.experiencia.teto},0 pts</h4>
      <dl>
        <div className="kv">
          <dt>Tempo comprovado (sem sobreposição)</dt>
          <dd>{fmtMeses(d.experiencia.meses_comprovados)}</dd>
        </div>
        <div className="kv">
          <dt>Mínimo exigido do nível</dt>
          <dd>{fmtMeses(d.experiencia.minimo_meses)}</dd>
        </div>
        <div className="kv">
          <dt>Tempo excedente (o que pontua)</dt>
          <dd>
            <b>{fmtMeses(d.experiencia.excedente_meses)}</b>
          </dd>
        </div>
      </dl>

      <details style={{ marginTop: 16 }}>
        <summary>Avisos metodológicos ({d.avisos_metodologicos.length})</summary>
        <ul style={{ margin: "8px 0 0 18px", fontSize: 13, color: "var(--muted)" }}>
          {d.avisos_metodologicos.map((m, i) => (
            <li key={i}>{m}</li>
          ))}
        </ul>
      </details>

      <hr className="divider" />
      <DocumentosSecao inscricaoId={inscricaoId} />
    </div>
  );
}

function DocumentosSecao({ inscricaoId }: { inscricaoId: string }) {
  const [docs, setDocs] = useState<DocumentoPainel[] | null>(null);
  const [erro, setErro] = useState("");

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("documentos_da_inscricao", { p_inscricao_id: inscricaoId })
      .then(({ data, error }: { data: DocumentoPainel[] | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else setDocs(data ?? []);
      });
  }, [inscricaoId]);

  return (
    <div>
      <h4>Documentos enviados {docs ? `(${docs.length})` : ""}</h4>
      <p className="hint">
        A leitura por IA (OpenAI) apenas transcreve o que está no documento — nunca decide se é válido. A conferência
        final é sempre da Comissão.
      </p>
      {erro ? <p className="err">{erro}</p> : null}
      {!docs ? (
        <p className="hint">Carregando…</p>
      ) : (
        <div style={{ display: "grid", gap: 8, marginTop: 10 }}>
          {docs.map((d) => (
            <LinhaDocumento key={d.id} doc={d} />
          ))}
        </div>
      )}
    </div>
  );
}

function LinhaDocumento({ doc }: { doc: DocumentoPainel }) {
  const [extracao, setExtracao] = useState(doc.extracao);
  const [analisando, setAnalisando] = useState(false);
  const [erro, setErro] = useState("");

  async function verArquivo() {
    setErro("");
    const { data, error } = await createClient().storage.from("documentos").createSignedUrl(doc.storage_path, 300);
    if (error) return setErro(error.message);
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }

  async function analisar() {
    setErro("");
    setAnalisando(true);
    try {
      const r = await fetch("/api/extrair-documento", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ documentoId: doc.id }),
      });
      const j = await r.json();
      if (!r.ok) throw new Error(j.erro || "Falha na extração.");
      setExtracao(j.extracao);
    } catch (e) {
      setErro(e instanceof Error ? e.message : "Falha na extração.");
    } finally {
      setAnalisando(false);
    }
  }

  return (
    <div className="doc-row" style={{ padding: "10px 12px" }}>
      <div style={{ display: "flex", justifyContent: "space-between", gap: 12, flexWrap: "wrap", alignItems: "center" }}>
        <div>
          <strong style={{ fontSize: 14 }}>{ROTULO_DOCUMENTO[doc.tipo]}</strong>
          <div className="hint">{doc.nome_original}</div>
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          <button type="button" className="btn btn-sm" onClick={() => void verArquivo()}>
            Ver arquivo
          </button>
          <button type="button" className="btn btn-sm" disabled={analisando} onClick={() => void analisar()}>
            {analisando ? <span className="spin" aria-hidden /> : null} {extracao ? "Analisar de novo" : "Analisar com IA"}
          </button>
        </div>
      </div>
      {erro ? <p className="err" style={{ marginTop: 6 }}>{erro}</p> : null}
      {extracao ? (
        <div style={{ marginTop: 10, background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 8, padding: 10, fontSize: 13 }}>
          {!extracao.json_extraido.legivel ? (
            <p style={{ color: "var(--err)" }}>⚠ A IA sinalizou que este documento está ilegível ou insuficiente.</p>
          ) : null}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: 6 }}>
            {Object.entries(extracao.json_extraido.campos)
              .filter(([, v]) => v !== null && v !== "")
              .map(([campo, valor]) => (
                <div key={campo}>
                  <div className="hint" style={{ textTransform: "capitalize" }}>{campo.replace(/_/g, " ")}</div>
                  <div>{String(valor)}</div>
                </div>
              ))}
          </div>
          {extracao.json_extraido.observacoes ? <p className="hint" style={{ marginTop: 8 }}>{extracao.json_extraido.observacoes}</p> : null}
          <p className="hint" style={{ marginTop: 8 }}>
            Confiança informada pela IA: {(extracao.json_extraido.confianca_geral * 100).toFixed(0)}% · Analisado em {new Date(extracao.criado_em).toLocaleString("pt-BR")}
          </p>
        </div>
      ) : null}
    </div>
  );
}

function TabelaItens({ itens }: { itens: { denominacao: string; pontos: number; motivo_rejeicao: string | null; observacao: string | null; extra: string }[] }) {
  return (
    <div style={{ display: "grid", gap: 8 }}>
      {itens.map((it, i) => (
        <div key={i} className="doc-row" style={{ padding: "10px 12px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
            <div>
              <strong style={{ fontSize: 14 }}>{it.denominacao}</strong>
              <div className="hint">{it.extra}</div>
            </div>
            <div style={{ textAlign: "right" }}>
              <span className={`tag ${it.pontos > 0 ? "tag-nao" : "tag-obrig"}`}>{it.pontos > 0 ? `+${it.pontos.toFixed(1)} pts` : "0 pts"}</span>
            </div>
          </div>
          {it.motivo_rejeicao ? <p className="hint" style={{ color: "var(--err)", marginTop: 6 }}>{it.motivo_rejeicao}</p> : null}
          {it.observacao ? <p className="hint" style={{ marginTop: 6 }}>{it.observacao}</p> : null}
        </div>
      ))}
    </div>
  );
}
