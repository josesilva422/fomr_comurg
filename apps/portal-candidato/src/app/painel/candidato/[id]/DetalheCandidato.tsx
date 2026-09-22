"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import { fmtMeses, type AvaliacaoDetalhada } from "@/lib/pontuacao";
import { ROTULO_DOCUMENTO, type TipoDocumento } from "@/lib/tipos-inscricao";
import type { Grupo, Nivel } from "@/lib/tipos";

const fmtCPF = (v: string) => v.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4");
const fmtData = (iso: string | null) => (iso ? new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(iso)) : "—");
const fmtDataCurta = (iso: string) => iso.split("-").reverse().join("/");

export interface Resumo {
  nome: string;
  cpf: string;
  email: string;
  telefone: string;
  grupo: Grupo;
  nivel: Nivel;
  status: string;
  submetida_em: string | null;
  curso_graduacao: string | null;
  grau_graduacao: "bacharelado" | "licenciatura" | "tecnologico" | null;
  instituicao_graduacao: string | null;
  data_colacao: string | null;
  formato_diploma: "fisico" | "digital" | null;
  codigo_diploma_digital: string | null;
  diploma_provisorio: boolean;
  diploma_exterior: boolean;
  cota_pcd: boolean;
  cota_racial: boolean;
  solicitou_isencao: boolean;
}

const ROTULO_GRAU: Record<string, string> = { bacharelado: "Bacharelado", licenciatura: "Licenciatura", tecnologico: "Tecnólogo" };
const PONTOS_MINIMOS_ENTREVISTA = 35; // edital, item 6.4.4

interface Comparacao {
  campo: string;
  documento_diz: string | null;
  confere: "sim" | "nao" | "nao_mencionado";
}
interface VerificacaoIA {
  legivel: boolean;
  comparacoes: Comparacao[];
  observacoes_gerais: string | null;
  confianca_geral: number;
}
interface Extracao {
  json_extraido: VerificacaoIA;
  criado_em: string;
}
interface DocumentoPainel {
  id: string;
  tipo: TipoDocumento;
  nome_original: string;
  storage_path: string;
  mime: string;
  tamanho_bytes: number;
  enviado_em: string;
  extracao: Extracao | null;
}

function Barra({ valor, teto }: { valor: number; teto: number }) {
  return (
    <div className="barra">
      <i style={{ width: `${Math.min(100, (valor / teto) * 100)}%` }} />
    </div>
  );
}

export function DetalheCandidato({ inscricaoId, resumo, avaliacaoInicial }: { inscricaoId: string; resumo: Resumo; avaliacaoInicial: AvaliacaoDetalhada }) {
  const [avaliacao] = useState(avaliacaoInicial);
  const d = avaliacao.detalhamento;

  const convocavel = avaliacao.habilitado && avaliacao.total >= PONTOS_MINIMOS_ENTREVISTA;

  return (
    <>
      <div className="resumo-destaque">
        <div>
          <p className="eyebrow" style={{ color: "#8fd6ab" }}>
            Painel da Comissão
          </p>
          <div className="nome">{resumo.nome}</div>
          <div className="sub">
            {fmtCPF(resumo.cpf)} · {resumo.email} · {resumo.telefone}
          </div>
          <div className="chips">
            <span className="chip">
              {GRUPOS[resumo.grupo].nome} · {NIVEIS[resumo.nivel].nome}
            </span>
            <span className="chip">{resumo.status === "aguardando_isencao" ? "Aguardando isenção" : "Submetida"}</span>
            <span className="chip">Enviada em {fmtData(resumo.submetida_em)}</span>
            {resumo.cota_pcd ? <span className="chip">PcD</span> : null}
            {resumo.cota_racial ? <span className="chip">Cota racial</span> : null}
            {resumo.solicitou_isencao ? <span className="chip">Isenção solicitada</span> : null}
          </div>
        </div>
        <div className="resumo-destaque-total">
          <span className={`pill ${avaliacao.habilitado ? "pill-ok" : "pill-err"}`} style={{ marginBottom: 8, display: "inline-flex" }}>
            {avaliacao.habilitado ? "Habilitado" : "Inabilitado"}
          </span>
          <div className="num">{avaliacao.total.toFixed(1)}</div>
          <small>de 60,0 pontos possíveis</small>
          {avaliacao.habilitado ? (
            <div style={{ marginTop: 6 }}>
              <span className={`pill ${convocavel ? "pill-ok" : "pill-muted"}`}>
                {convocavel ? `Atinge os ${PONTOS_MINIMOS_ENTREVISTA} pts da entrevista` : `Abaixo dos ${PONTOS_MINIMOS_ENTREVISTA} pts da entrevista`}
              </span>
            </div>
          ) : null}
        </div>
      </div>

      {!avaliacao.habilitado && avaliacao.motivos.length ? (
        <div className="alert alert-err">
          <div>
            <p>
              <b>Motivos da inabilitação:</b>
            </p>
            <ul style={{ margin: "6px 0 0 18px" }}>
              {avaliacao.motivos.map((m, i) => (
                <li key={i}>{m.mensagem}</li>
              ))}
            </ul>
          </div>
        </div>
      ) : null}

      <div className="topico">
        <h3>Graduação (requisito de habilitação)</h3>
        <p className="sub">Não pontua — é a base para poder concorrer. Itens 3.2 a 3.4 e 5.1 do edital.</p>
        <dl>
          <div className="kv">
            <dt>Curso</dt>
            <dd>
              {resumo.curso_graduacao ?? "—"} {resumo.grau_graduacao ? `(${ROTULO_GRAU[resumo.grau_graduacao] ?? resumo.grau_graduacao})` : ""}
            </dd>
          </div>
          <div className="kv">
            <dt>Instituição</dt>
            <dd>{resumo.instituicao_graduacao ?? "—"}</dd>
          </div>
          <div className="kv">
            <dt>Data de colação de grau</dt>
            <dd>{resumo.data_colacao ? fmtDataCurta(resumo.data_colacao) : "—"}</dd>
          </div>
          <div className="kv">
            <dt>Diploma</dt>
            <dd>
              {resumo.formato_diploma === "digital" ? "Digital" : "Físico"}
              {resumo.formato_diploma === "digital" && resumo.codigo_diploma_digital ? ` · código: ${resumo.codigo_diploma_digital}` : ""}
              {resumo.diploma_provisorio ? " · certificado provisório (com histórico escolar)" : ""}
              {resumo.diploma_exterior ? " · emitido no exterior (com revalidação)" : ""}
            </dd>
          </div>
        </dl>
        {resumo.grau_graduacao === "tecnologico" ? (
          <p className="motivo" style={{ marginTop: 8 }}>
            ⚠ Curso tecnológico — não é aceito em nenhum grupo ou nível (item 5.1.6).
          </p>
        ) : null}
      </div>

      <div className="criterio">
        <div className="criterio-head">
          <h4>Pós-graduação e títulos adicionais</h4>
          <span className="valor">
            {d.formacao.total.toFixed(1)} / {d.formacao.teto.toFixed(1)} pts
          </span>
        </div>
        <Barra valor={d.formacao.total} teto={d.formacao.teto} />
        {d.formacao.itens.length === 0 ? (
          <p className="hint" style={{ marginTop: 10 }}>
            Nenhum título declarado.
          </p>
        ) : (
          d.formacao.itens.map((it) => (
            <div className={`linha-item${it.pontos === 0 ? " rejeitado" : ""}`} key={it.id}>
              <div className="linha-item-head">
                <div>
                  <strong>{it.denominacao}</strong>
                  <small>
                    {it.tipo} · concluído em {fmtDataCurta(it.data_conclusao)}
                  </small>
                </div>
                <span className={`pill ${it.pontos > 0 ? "pill-ok" : "pill-muted"}`}>{it.pontos > 0 ? `+${it.pontos.toFixed(1)} pts` : "0 pts"}</span>
              </div>
              {it.motivo_rejeicao ? <p className="motivo">{it.motivo_rejeicao}</p> : null}
              {it.observacao ? <p className="aviso">⚠ {it.observacao}</p> : null}
            </div>
          ))
        )}
      </div>

      <div className="criterio">
        <div className="criterio-head">
          <h4>Cursos e certificações específicas</h4>
          <span className="valor">
            {d.cursos.total.toFixed(1)} / {d.cursos.teto.toFixed(1)} pts
          </span>
        </div>
        <Barra valor={d.cursos.total} teto={d.cursos.teto} />
        {d.cursos.itens.length === 0 ? (
          <p className="hint" style={{ marginTop: 10 }}>
            Nenhum curso ou certificação declarado.
          </p>
        ) : (
          d.cursos.itens.map((it) => (
            <div className={`linha-item${it.pontos === 0 ? " rejeitado" : ""}`} key={it.id}>
              <div className="linha-item-head">
                <div>
                  <strong>{it.denominacao}</strong>
                  <small>
                    {it.carga_horaria ? `${it.carga_horaria}h · ` : ""}
                    concluído em {fmtDataCurta(it.data_conclusao)}
                    {!it.no_catalogo_do_grupo ? " · fora do catálogo" : ""}
                  </small>
                </div>
                <span className={`pill ${it.pontos > 0 ? "pill-ok" : "pill-muted"}`}>{it.pontos > 0 ? `+${it.pontos.toFixed(1)} pts` : "0 pts"}</span>
              </div>
              {it.motivo_rejeicao ? <p className="motivo">{it.motivo_rejeicao}</p> : null}
              {it.observacao ? <p className="aviso">⚠ {it.observacao}</p> : null}
            </div>
          ))
        )}
      </div>

      <div className="criterio">
        <div className="criterio-head">
          <h4>Experiência profissional específica</h4>
          <span className="valor">
            {d.experiencia.pontos.toFixed(1)} / {d.experiencia.teto.toFixed(1)} pts
          </span>
        </div>
        <Barra valor={d.experiencia.pontos} teto={d.experiencia.teto} />
        <dl style={{ marginTop: 10 }}>
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
      </div>

      <details style={{ marginTop: 8 }}>
        <summary>Por que essas regras? ({d.avisos_metodologicos.length} avisos)</summary>
        <ul style={{ margin: "8px 0 0 18px", fontSize: 13, color: "var(--muted)" }}>
          {d.avisos_metodologicos.map((m, i) => (
            <li key={i}>{m}</li>
          ))}
        </ul>
      </details>

      <hr className="divider" />
      <DocumentosSecao inscricaoId={inscricaoId} />
    </>
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
      <h3>Documentos enviados {docs ? `(${docs.length})` : ""}</h3>
      <p className="hint">
        A IA compara o que o candidato declarou com o que cada documento realmente diz — nunca decide sozinha se
        o documento é válido. A conferência final é sempre da Comissão.
      </p>
      {erro ? <p className="err">{erro}</p> : null}
      {!docs ? (
        <p className="hint">Carregando…</p>
      ) : docs.length === 0 ? (
        <div className="empty">Nenhum documento enviado.</div>
      ) : (
        <div style={{ display: "grid", gap: 12, marginTop: 10 }}>
          {docs.map((doc) => (
            <LinhaDocumento key={doc.id} doc={doc} />
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
      if (!r.ok) throw new Error(j.erro || "Falha na verificação.");
      setExtracao(j.extracao);
    } catch (e) {
      setErro(e instanceof Error ? e.message : "Falha na verificação.");
    } finally {
      setAnalisando(false);
    }
  }

  const classePorConfere = { sim: "confere", nao: "nao-confere", nao_mencionado: "nao-mencionado" } as const;
  const rotuloPorConfere = { sim: "✓ Confere", nao: "✗ Não confere", nao_mencionado: "➖ Não mencionado" } as const;

  return (
    <div className="linha-item">
      <div className="linha-item-head">
        <div>
          <strong>{ROTULO_DOCUMENTO[doc.tipo]}</strong>
          <small>{doc.nome_original}</small>
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          <button type="button" className="btn btn-sm" onClick={() => void verArquivo()}>
            Ver arquivo
          </button>
          <button type="button" className="btn btn-sm btn-primary" disabled={analisando} onClick={() => void analisar()}>
            {analisando ? <span className="spin" aria-hidden /> : null} {extracao ? "Verificar de novo" : "Verificar com IA"}
          </button>
        </div>
      </div>
      {erro ? <p className="motivo">{erro}</p> : null}
      {extracao ? (
        <div style={{ marginTop: 12 }}>
          {!extracao.json_extraido.legivel ? <p className="motivo">⚠ A IA sinalizou que este documento está ilegível ou insuficiente para conferência.</p> : null}
          <div className="comparacao">
            {extracao.json_extraido.comparacoes.map((c, i) => (
              <div key={i} className={`comparacao-linha ${classePorConfere[c.confere]}`}>
                <div className="comparacao-campo">{c.campo}</div>
                <div className="comparacao-valores">
                  <span>{rotuloPorConfere[c.confere]}</span>
                  <span>
                    <b>O documento diz:</b> {c.documento_diz ?? <em>nada sobre isso</em>}
                  </span>
                </div>
              </div>
            ))}
          </div>
          {extracao.json_extraido.observacoes_gerais ? <p className="hint" style={{ marginTop: 8 }}>{extracao.json_extraido.observacoes_gerais}</p> : null}
          <p className="hint" style={{ marginTop: 8 }}>
            Confiança informada pela IA: {(extracao.json_extraido.confianca_geral * 100).toFixed(0)}% · Verificado em {new Date(extracao.criado_em).toLocaleString("pt-BR")}
          </p>
        </div>
      ) : null}
    </div>
  );
}
