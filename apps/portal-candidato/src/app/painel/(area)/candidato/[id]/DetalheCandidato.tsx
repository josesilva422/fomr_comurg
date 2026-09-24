"use client";

import { useEffect, useState, type ReactNode } from "react";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import { fmtMeses, type AvaliacaoDetalhada } from "@/lib/pontuacao";
import { ROTULO_DOCUMENTO, type TipoDocumento } from "@/lib/tipos-inscricao";
import { montarSecoes, type RegistroRelatorio } from "@/lib/relatorio";
import type { Grupo, Nivel } from "@/lib/tipos";
import { BarraCaixas, Caixa, useSinalCaixas, type SinalCaixas } from "@/components/Caixa";
import { EntrevistaSecao } from "./EntrevistaSecao";

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
  pagina: number | null;
  confere: "sim" | "nao" | "nao_mencionado";
}
interface VerificacaoIA {
  legivel: boolean;
  comparacoes: Comparacao[];
  observacoes_gerais: string | null;
  // Opcionais: extrações feitas antes de 22/09/2026 (versões v2 a v5 do prompt) não têm esses campos, ou têm
  // versões antigas deles (texto_extraido virou resumo_documento na v6).
  indicios_adulteracao?: { suspeita: boolean; detalhes: string | null };
  resumo_documento?: string;
  texto_extraido?: string;
  tipo_documento?: { o_que_e: string; bate_com_esperado: boolean; observacao: string | null };
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

type Aba = "analise" | "entrevista" | "formulario" | "documentos";
const ABAS: { chave: Aba; rotulo: string }[] = [
  { chave: "analise", rotulo: "Análise curricular" },
  { chave: "entrevista", rotulo: "Entrevista técnica" },
  { chave: "formulario", rotulo: "Formulário respondido" },
  { chave: "documentos", rotulo: "Documentos" },
];

export function DetalheCandidato({ inscricaoId, resumo, avaliacaoInicial, abaInicial = "analise" }: { inscricaoId: string; resumo: Resumo; avaliacaoInicial: AvaliacaoDetalhada; abaInicial?: Aba }) {
  const [avaliacao] = useState(avaliacaoInicial);
  const [aba, setAba] = useState<Aba>(abaInicial);
  const [baixando, setBaixando] = useState(false);
  const [erroPdf, setErroPdf] = useState("");
  const convocavel = avaliacao.habilitado && avaliacao.total >= PONTOS_MINIMOS_ENTREVISTA;

  // PDF do formulário deste candidato (mesmo relatório do menu "Relatórios", filtrado pelo CPF).
  async function baixarPdf() {
    setErroPdf("");
    setBaixando(true);
    try {
      const res = await fetch(`/api/painel/relatorio?formato=pdf&busca=${encodeURIComponent(resumo.cpf)}`);
      if (!res.ok) throw new Error((await res.json().catch(() => null))?.erro ?? "Não foi possível gerar o PDF.");
      const nome = /filename="([^"]+)"/.exec(res.headers.get("Content-Disposition") ?? "")?.[1] ?? "formulario.pdf";
      const url = URL.createObjectURL(await res.blob());
      const a = document.createElement("a");
      a.href = url;
      a.download = nome;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      setErroPdf(e instanceof Error ? e.message : "Falha ao baixar o PDF.");
    } finally {
      setBaixando(false);
    }
  }

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
          <div style={{ marginTop: 12 }}>
            <button type="button" className="btn btn-sm btn-baixar" disabled={baixando} onClick={() => void baixarPdf()}>
              {baixando ? "Gerando PDF…" : "Baixar formulário (PDF)"}
            </button>
            {erroPdf ? <p className="motivo" style={{ marginTop: 6, color: "#ffd6d6" }}>{erroPdf}</p> : null}
          </div>
        </div>
        <div className="resumo-destaque-total">
          <span className={`pill ${avaliacao.habilitado ? "pill-ok" : "pill-err"}`} style={{ marginBottom: 8, display: "inline-flex" }}>
            {avaliacao.habilitado ? "Habilitado" : "Inabilitado"}
          </span>
          <div className="num">{avaliacao.total.toFixed(1)}</div>
          <small>de 60,0 pontos possíveis (AC)</small>
          {avaliacao.habilitado ? (
            <div style={{ marginTop: 6 }}>
              <span className={`pill ${convocavel ? "pill-ok" : "pill-muted"}`}>
                {convocavel ? `Atinge os ${PONTOS_MINIMOS_ENTREVISTA} pts da entrevista` : `Abaixo dos ${PONTOS_MINIMOS_ENTREVISTA} pts da entrevista`}
              </span>
            </div>
          ) : null}
        </div>
      </div>

      <div className="abas" role="tablist" aria-label="Etapas do candidato">
        {ABAS.map((a) => (
          <button key={a.chave} type="button" role="tab" aria-selected={aba === a.chave} className={`aba${aba === a.chave ? " is-ativa" : ""}`} onClick={() => setAba(a.chave)}>
            {a.rotulo}
          </button>
        ))}
      </div>

      {/* Todas as abas ficam montadas (só escondidas) para não perder o que está sendo digitado na ficha da entrevista. */}
      <div role="tabpanel" hidden={aba !== "analise"}>
        <AnaliseAba resumo={resumo} avaliacao={avaliacao} />
      </div>
      <div role="tabpanel" hidden={aba !== "entrevista"}>
        <EntrevistaSecao inscricaoId={inscricaoId} />
      </div>
      <div role="tabpanel" hidden={aba !== "formulario"}>
        <FormularioAba inscricaoId={inscricaoId} />
      </div>
      <div role="tabpanel" hidden={aba !== "documentos"}>
        <DocumentosSecao inscricaoId={inscricaoId} />
      </div>
    </>
  );
}

function SeloPts({ valor, teto }: { valor: number; teto: number }) {
  return (
    <span className={`pill ${valor > 0 ? "pill-ok" : "pill-muted"}`}>
      {valor.toFixed(1)} / {teto.toFixed(1)} pts
    </span>
  );
}

function AnaliseAba({ resumo, avaliacao }: { resumo: Resumo; avaliacao: AvaliacaoDetalhada }) {
  const d = avaliacao.detalhamento;
  const { sinal, abrirTodas, recolherTodas } = useSinalCaixas();
  return (
    <div>
      <BarraCaixas abrirTodas={abrirTodas} recolherTodas={recolherTodas} />

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

      <Caixa titulo="Graduação (requisito de habilitação)" selo={<span className="pill pill-muted">não pontua</span>} sinal={sinal}>
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
      </Caixa>

      <Caixa titulo="Pós-graduação e títulos adicionais" selo={<SeloPts valor={d.formacao.total} teto={d.formacao.teto} />} sinal={sinal}>
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
      </Caixa>

      <Caixa titulo="Cursos e certificações específicas" selo={<SeloPts valor={d.cursos.total} teto={d.cursos.teto} />} sinal={sinal}>
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
      </Caixa>

      <Caixa titulo="Experiência profissional específica" selo={<SeloPts valor={d.experiencia.pontos} teto={d.experiencia.teto} />} sinal={sinal}>
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
      </Caixa>

      <Caixa titulo="Por que essas regras?" selo={<span className="pill pill-muted">{d.avisos_metodologicos.length} avisos</span>} aberta={false} sinal={sinal}>
        <ul style={{ margin: "0 0 0 18px", fontSize: 13, color: "var(--muted)" }}>
          {d.avisos_metodologicos.map((m, i) => (
            <li key={i}>{m}</li>
          ))}
        </ul>
      </Caixa>
    </div>
  );
}

// Respostas do formulário, na mesma ordem e com as mesmas perguntas do relatório em Excel/PDF (lib/relatorio).
function FormularioAba({ inscricaoId }: { inscricaoId: string }) {
  const [registro, setRegistro] = useState<RegistroRelatorio | null>(null);
  const [erro, setErro] = useState("");
  const { sinal, abrirTodas, recolherTodas } = useSinalCaixas();

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("formulario_da_inscricao", { p_inscricao_id: inscricaoId })
      .then(({ data, error }: { data: RegistroRelatorio | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else setRegistro(data);
      });
  }, [inscricaoId]);

  if (erro) return <p className="err">{erro}</p>;
  if (!registro) return <p className="hint">Carregando formulário…</p>;

  return (
    <div>
      <BarraCaixas abrirTodas={abrirTodas} recolherTodas={recolherTodas} />
      {montarSecoes(registro).map((s) => (
        <Caixa key={s.titulo} titulo={s.titulo} sinal={sinal}>
          <dl>
            {s.itens.map((i) => (
              <div className="kv" key={i.pergunta}>
                <dt>{i.pergunta}</dt>
                <dd style={{ whiteSpace: "pre-line" }}>{i.resposta}</dd>
              </div>
            ))}
          </dl>
        </Caixa>
      ))}
    </div>
  );
}

function DocumentosSecao({ inscricaoId }: { inscricaoId: string }) {
  const [docs, setDocs] = useState<DocumentoPainel[] | null>(null);
  const [erro, setErro] = useState("");
  const { sinal, abrirTodas, recolherTodas } = useSinalCaixas();

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
      <p className="hint" style={{ marginTop: 0 }}>
        A IA compara o que o candidato declarou com o que cada documento realmente diz — nunca decide sozinha se o documento é válido. A conferência
        final é sempre da Comissão.
      </p>
      {docs && docs.length > 0 ? <BarraCaixas abrirTodas={abrirTodas} recolherTodas={recolherTodas} /> : null}
      {erro ? <p className="err">{erro}</p> : null}
      {!docs ? (
        <p className="hint">Carregando…</p>
      ) : docs.length === 0 ? (
        <div className="empty">Nenhum documento enviado.</div>
      ) : (
        docs.map((doc) => <LinhaDocumento key={doc.id} doc={doc} sinal={sinal} />)
      )}
    </div>
  );
}

function seloDaVerificacao(extracao: Extracao | null): ReactNode {
  if (!extracao) return <span className="pill pill-muted">Não verificado</span>;
  const j = extracao.json_extraido;
  if (j.tipo_documento && !j.tipo_documento.bate_com_esperado) return <span className="pill pill-err">⚠ Tipo diferente</span>;
  if (j.comparacoes.some((c) => c.confere === "nao")) return <span className="pill pill-err">✗ Diverge</span>;
  if (!j.legivel) return <span className="pill pill-err">Ilegível</span>;
  return <span className="pill pill-ok">✓ Confere</span>;
}

function LinhaDocumento({ doc, sinal }: { doc: DocumentoPainel; sinal: SinalCaixas }) {
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
    <Caixa
      titulo={
        <>
          {ROTULO_DOCUMENTO[doc.tipo]} <small className="caixa-sub">{doc.nome_original}</small>
        </>
      }
      selo={seloDaVerificacao(extracao)}
      aberta={false}
      sinal={sinal}
    >
      <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
        <button type="button" className="btn btn-sm" onClick={() => void verArquivo()}>
          Ver arquivo
        </button>
        <button type="button" className="btn btn-sm btn-primary" disabled={analisando} onClick={() => void analisar()}>
          {analisando ? <span className="spin" aria-hidden /> : null} {extracao ? "Verificar de novo" : "Verificar com IA"}
        </button>
      </div>
      {erro ? <p className="motivo">{erro}</p> : null}
      {extracao ? (
        <div style={{ marginTop: 12 }}>
          {extracao.json_extraido.tipo_documento ? (
            extracao.json_extraido.tipo_documento.bate_com_esperado ? (
              <p className="motivo" style={{ color: "var(--ok-text)" }}>
                ✓ O documento confere com o tipo esperado ({ROTULO_DOCUMENTO[doc.tipo]}): {extracao.json_extraido.tipo_documento.o_que_e}
              </p>
            ) : (
              <p className="motivo" style={{ fontWeight: 700 }}>
                ⚠ Este documento NÃO parece ser {ROTULO_DOCUMENTO[doc.tipo].toLowerCase()} — parece ser: {extracao.json_extraido.tipo_documento.o_que_e}
                {extracao.json_extraido.tipo_documento.observacao ? ` (${extracao.json_extraido.tipo_documento.observacao})` : ""}
              </p>
            )
          ) : null}
          {!extracao.json_extraido.legivel ? <p className="motivo">⚠ A IA sinalizou que este documento está ilegível ou insuficiente para conferência.</p> : null}
          {extracao.json_extraido.indicios_adulteracao?.suspeita ? (
            <p className="motivo">
              ⚠ Indício de possível adulteração — <b>não é uma conclusão, só um ponto para a Comissão olhar com atenção</b>:{" "}
              {extracao.json_extraido.indicios_adulteracao.detalhes ?? "sem detalhes."}
            </p>
          ) : null}
          <div className="comparacao">
            {extracao.json_extraido.comparacoes.map((c, i) => (
              <div key={i} className={`comparacao-linha ${classePorConfere[c.confere]}`}>
                <div className="comparacao-campo">{c.campo}</div>
                <div className="comparacao-valores">
                  <span>
                    {rotuloPorConfere[c.confere]}
                    {c.pagina != null ? ` · pág. ${c.pagina}` : ""}
                  </span>
                  <span>
                    <b>O documento diz:</b> {c.documento_diz ?? <em>nada sobre isso</em>}
                  </span>
                </div>
              </div>
            ))}
          </div>
          {extracao.json_extraido.observacoes_gerais ? <p className="hint" style={{ marginTop: 8 }}>{extracao.json_extraido.observacoes_gerais}</p> : null}
          {extracao.json_extraido.resumo_documento ? (
            <p className="hint" style={{ marginTop: 8 }}>
              <b>Resumo do documento:</b> {extracao.json_extraido.resumo_documento}
            </p>
          ) : extracao.json_extraido.texto_extraido ? (
            <details style={{ marginTop: 8 }}>
              <summary>Transcrição completa do documento (extração antiga, sem resumo)</summary>
              <p className="hint" style={{ marginTop: 6, whiteSpace: "pre-wrap" }}>
                {extracao.json_extraido.texto_extraido}
              </p>
            </details>
          ) : null}
          <p className="hint" style={{ marginTop: 8 }}>
            Confiança informada pela IA: {(extracao.json_extraido.confianca_geral * 100).toFixed(0)}% · Verificado em {new Date(extracao.criado_em).toLocaleString("pt-BR")}
          </p>
        </div>
      ) : null}
    </Caixa>
  );
}
