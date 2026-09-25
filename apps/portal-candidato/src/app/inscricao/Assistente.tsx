"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import type { Candidato, Inscricao } from "@/lib/tipos";
import type { CursoDeclarado, Documento, Pendencia, Titulo, Vinculo } from "@/lib/tipos-inscricao";
import type { Contexto, RascunhoVinculo } from "./contexto";
import { PassoCotas } from "./PassoCotas";
import { PassoDados } from "./PassoDados";
import { PassoExperiencia } from "./PassoExperiencia";
import { PassoFormacao } from "./PassoFormacao";
import { PassoPagamento } from "./PassoPagamento";
import { PassoRevisao } from "./PassoRevisao";
import { PassoVaga } from "./PassoVaga";
import { MeuFormulario } from "./MeuFormulario";
import { MeuConviteEntrevista } from "./MeuConviteEntrevista";
import { ResultadoIsencao, situacaoIsencao, useMinhaIsencao } from "./ResultadoIsencao";

const PASSOS = [
  "Dados pessoais",
  "Grupo e nível",
  "Formação",
  "Experiência",
  "Cotas e isenção",
  "Pagamento (Pix)",
  "Revisão e envio",
] as const;

export interface DadosIniciais {
  userId: string;
  email: string;
  candidato: Candidato | null;
  inscricao: Inscricao | null;
  documentos: Documento[];
  titulos: Titulo[];
  cursos: CursoDeclarado[];
  vinculos: Vinculo[];
  pendencias: Pendencia[];
}

export function Assistente(props: DadosIniciais) {
  const [candidato, setCandidato] = useState(props.candidato);
  const [inscricao, setInscricao] = useState(props.inscricao);
  const [documentos, setDocumentos] = useState(props.documentos);
  const [titulos, setTitulos] = useState(props.titulos);
  const [cursos, setCursos] = useState(props.cursos);
  const [vinculos, setVinculos] = useState(props.vinculos);
  const [pendencias, setPendencias] = useState(props.pendencias);
  const [rascunhosVinculosCV, setRascunhosVinculosCV] = useState<RascunhoVinculo[]>([]);

  // primeira etapa com pendência BLOQUEANTE (avisos, como título sem documento, não desviam o candidato)
  const [passo, setPasso] = useState(() => {
    const abertas = props.pendencias.filter((p) => p.bloqueia).map((p) => p.etapa).filter((n) => n >= 1 && n <= 6);
    return abertas.length ? Math.min(...abertas) : 7;
  });
  const [visitados, setVisitados] = useState<number[]>([]);

  const irPara = useCallback((n: number) => {
    setPasso((atual) => {
      setVisitados((v) => (v.includes(atual) ? v : [...v, atual]));
      return n;
    });
    window.scrollTo({ top: 0, behavior: "smooth" });
  }, []);

  /** Busca tudo de novo no banco (o RLS devolve só as linhas do próprio candidato) e recalcula as pendências. */
  const recarregar = useCallback(async (): Promise<Pendencia[]> => {
    const supabase = createClient();
    const [c, i, d, t, k, v, p] = await Promise.all([
      supabase.from("candidatos").select("*").maybeSingle(),
      supabase.from("inscricoes").select("*").maybeSingle(),
      supabase.from("documentos").select("*").eq("ativo", true).order("enviado_em"),
      supabase.from("titulos_declarados").select("*").order("created_at"),
      supabase.from("cursos_declarados").select("*").order("created_at"),
      supabase.from("vinculos_declarados").select("*").order("inicio"),
      supabase.rpc("verificar_inscricao"),
    ]);
    setCandidato((c.data as Candidato | null) ?? null);
    setInscricao((i.data as Inscricao | null) ?? null);
    setDocumentos((d.data as Documento[] | null) ?? []);
    setTitulos((t.data as Titulo[] | null) ?? []);
    setCursos((k.data as CursoDeclarado[] | null) ?? []);
    setVinculos((v.data as Vinculo[] | null) ?? []);
    const pend = (p.data as Pendencia[] | null) ?? [];
    setPendencias(pend);
    return pend;
  }, []);

  const ctx: Contexto = {
    userId: props.userId,
    email: props.email,
    candidato,
    inscricao,
    documentos,
    titulos,
    cursos,
    vinculos,
    pendencias,
    recarregar,
    irPara,
    rascunhosVinculosCV,
    definirRascunhosVinculosCV: setRascunhosVinculosCV,
  };

  const selada = inscricao != null && inscricao.status !== "rascunho";
  if (selada && inscricao) return <Enviada inscricao={inscricao} candidato={candidato} />;

  function statusDoPasso(n: number): { classe: string; texto: string } {
    if (n === passo) return { classe: "is-current", texto: "Etapa atual" };
    if (n > 1 && !candidato) return { classe: "", texto: "Preencha a etapa 1" };
    if (n === 7) return { classe: "", texto: "Conferir e enviar" };
    if (n === 5 && !visitados.includes(5) && pendencias.every((p) => p.etapa !== 5)) return { classe: "", texto: "Opcional" };
    const doPasso = pendencias.filter((p) => p.etapa === n);
    const bloqueantes = doPasso.filter((p) => p.bloqueia).length;
    if (bloqueantes > 0) return { classe: visitados.includes(n) ? "is-warn" : "", texto: `${bloqueantes} pendência${bloqueantes > 1 ? "s" : ""}` };
    const avisos = doPasso.length;
    if (avisos > 0) return { classe: "is-done", texto: `Completa · ${avisos} aviso${avisos > 1 ? "s" : ""}` };
    return { classe: "is-done", texto: "Completa" };
  }

  const chipVaga =
    inscricao?.grupo || inscricao?.nivel
      ? `${inscricao?.grupo ? GRUPOS[inscricao.grupo].nome : "Grupo —"} · ${inscricao?.nivel ? NIVEIS[inscricao.nivel].nome : "Nível —"}`
      : null;

  return (
    <main className="wrap layout">
      <aside className="rail" aria-label="Etapas da inscrição">
        <div className="rail-compact">
          <div className="rail-compact-top">
            <strong>Etapa {passo} de 7</strong>
            <span>{PASSOS[passo - 1]}</span>
          </div>
          <div className="bar">
            <i style={{ width: `${(passo / 7) * 100}%` }} />
          </div>
          <label className="rail-select">
            <span className="sr-only">Ir para outra etapa</span>
            <select
              value={passo}
              onChange={(e) => irPara(Number(e.target.value))}
              aria-label="Navegar entre as etapas da inscrição"
            >
              {PASSOS.map((nome, i) => {
                const n = i + 1;
                const st = statusDoPasso(n);
                const bloqueado = n > 1 && !candidato;
                return (
                  <option key={nome} value={n} disabled={bloqueado}>
                    {n}. {nome} — {st.texto}
                  </option>
                );
              })}
            </select>
          </label>
        </div>
        <ol className="rail-list">
          {PASSOS.map((nome, i) => {
            const n = i + 1;
            const st = statusDoPasso(n);
            const bloqueado = n > 1 && !candidato;
            return (
              <li key={nome}>
                <button
                  type="button"
                  className={`rail-item ${st.classe}`}
                  disabled={bloqueado}
                  aria-current={n === passo ? "step" : undefined}
                  onClick={() => irPara(n)}
                >
                  <span className="dot">{st.classe === "is-done" ? "✓" : n}</span>
                  <span className="lbl">
                    {nome}
                    <small>{st.texto}</small>
                  </span>
                </button>
              </li>
            );
          })}
        </ol>
        {chipVaga ? (
          <div className="rail-vaga">
            <b>Sua vaga</b>
            {chipVaga}
          </div>
        ) : null}
        <p className="rail-help">Você pode sair e continuar depois: o rascunho fica salvo. Depois de enviar, a inscrição é definitiva.</p>
      </aside>

      <div>
        {passo === 1 && <PassoDados key="p1" ctx={ctx} />}
        {passo === 2 && candidato && inscricao && <PassoVaga key="p2" ctx={ctx} />}
        {passo === 3 && candidato && inscricao && <PassoFormacao key="p3" ctx={ctx} />}
        {passo === 4 && candidato && inscricao && <PassoExperiencia key="p4" ctx={ctx} />}
        {passo === 5 && candidato && inscricao && <PassoCotas key="p5" ctx={ctx} />}
        {passo === 6 && candidato && inscricao && <PassoPagamento key="p6" ctx={ctx} />}
        {passo === 7 && candidato && inscricao && <PassoRevisao key="p7" ctx={ctx} />}
        <div className="actions" style={{ position: "static", background: "transparent", border: 0, padding: 0, marginTop: 18 }}>
          <button
            type="button"
            className="btn btn-ghost"
            style={{ visibility: passo === 1 ? "hidden" : "visible" }}
            onClick={() => irPara(Math.max(1, passo - 1))}
          >
            ← Voltar
          </button>
        </div>
      </div>
    </main>
  );
}

/* ------------------------------------------------------------------ Inscrição enviada (selada) */

function Enviada({ inscricao, candidato }: { inscricao: Inscricao; candidato: Candidato | null }) {
  const noFluxoIsencao = inscricao.status === "aguardando_isencao";
  const isencao = useMinhaIsencao(noFluxoIsencao);
  const rejeitada = inscricao.status === "indeferida";
  const rejeicao = useRejeicao(rejeitada);
  const situacao =
    inscricao.status === "homologada"
      ? "inscrição aprovada"
      : rejeitada
        ? "inscrição rejeitada"
        : noFluxoIsencao
          ? situacaoIsencao(isencao.res, isencao.docs)
          : "recebida, aguardando homologação";
  const protocolo = `PSS-2026-${inscricao.id.slice(0, 8).toUpperCase()}`;
  const quando = inscricao.submetida_em
    ? new Intl.DateTimeFormat("pt-BR", { dateStyle: "long", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(inscricao.submetida_em))
    : "";
  return (
    <main className="wrap" style={{ padding: "24px 16px 64px" }}>
      <section className="card success">
        <div className="ok" aria-hidden>
          ✓
        </div>
        <h2>Solicitação enviada</h2>
        <p className="lead" style={{ margin: "8px auto 0" }}>
          {candidato ? `${candidato.nome.split(" ")[0]}, s` : "S"}ua inscrição foi recebida e está bloqueada para alterações. Guarde
          o número do protocolo.
        </p>
        <div className="protocolo">{protocolo}</div>
        {quando ? <p style={{ color: "var(--muted)", fontSize: 14 }}>Enviada em {quando}</p> : null}
        <p style={{ color: "var(--muted)", fontSize: 14, marginTop: 6 }}>
          Situação:{" "}
          <b>{situacao}</b>
        </p>
      </section>
      {rejeitada ? (
        <section className="card" style={{ marginTop: 16 }}>
          <h3>Inscrição rejeitada</h3>
          <div className="alert alert-err">
            <p>
              <b>Motivo informado pela Comissão:</b> {rejeicao ? (rejeicao.motivo ?? "—") : "carregando…"}
            </p>
          </div>
          <p className="hint">
            Cabe recurso contra o indeferimento da inscrição (item 9.1, alínea b do edital), no prazo de 3 dias úteis contados do dia útil seguinte à
            publicação do resultado (Anexo IV: 21, 22 e 23/10/2026). O recurso é enviado exclusivamente pelo e-mail pss2026comurg@comurg.com.br, com o
            formulário do Anexo VI preenchido e assinado, e &quot;RECURSO&quot;, a etapa, o seu nome e o Grupo/Nível no assunto (item 9.2).
          </p>
        </section>
      ) : null}
      {inscricao.status === "homologada" || inscricao.status === "submetida" || noFluxoIsencao ? <MeuConviteEntrevista /> : null}
      {noFluxoIsencao ? <ResultadoIsencao inscricaoId={inscricao.id} isencao={isencao} /> : null}
      <MeuFormulario />
    </main>
  );
}

/** Motivo da rejeição da inscrição (publico.minha_decisao_inscricao); só busca quando a inscrição foi rejeitada. */
function useRejeicao(ativo: boolean) {
  const [res, setRes] = useState<{ motivo: string | null } | null>(null);
  useEffect(() => {
    if (!ativo) return;
    let vivo = true;
    createClient()
      .rpc("minha_decisao_inscricao")
      .then(({ data }: { data: { decisao: string; motivo: string | null }[] | null }) => {
        if (vivo) setRes({ motivo: data?.[0]?.motivo ?? null });
      });
    return () => {
      vivo = false;
    };
  }, [ativo]);
  return res;
}
