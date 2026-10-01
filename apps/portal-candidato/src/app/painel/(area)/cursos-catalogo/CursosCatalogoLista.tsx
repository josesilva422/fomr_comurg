"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

interface LinhaCurso {
  curso_id: string;
  inscricao_id: string;
  nome: string;
  cpf: string;
  grupo: string;
  nivel: string;
  tipo: "curso" | "certificacao";
  denominacao: string;
  carga_horaria: number | null;
  data_conclusao: string;
  pontos: number;
  decisao: "aceito" | "recusado" | null;
  motivo: string | null;
  decidido_por_nome: string;
  decidido_em: string | null;
}

const fmtCPF = (v: string) => v.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4");
const fmtData = (v: string) => v.split("-").reverse().join("/");
const fmtDataHora = (v: string | null) => (v ? new Date(v).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" }) : "—");

export function CursosCatalogoLista() {
  const [linhas, setLinhas] = useState<LinhaCurso[] | null>(null);
  const [erro, setErro] = useState("");
  const [versao, setVersao] = useState(0);
  const [aberta, setAberta] = useState<string | null>(null);

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("listar_cursos_fora_catalogo")
      .then(({ data, error }: { data: LinhaCurso[] | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else {
          setErro("");
          setLinhas(data ?? []);
        }
      });
  }, [versao]);

  if (erro) return <p className="err">{erro}</p>;
  if (!linhas) return <p className="hint">Carregando…</p>;
  if (!linhas.length) return <div className="empty">Nenhum curso ou certificação fora do catálogo até o momento.</div>;

  const pendentes = linhas.filter((l) => !l.decisao).length;

  return (
    <div>
      <p className="hint" style={{ marginTop: 0 }}>
        {linhas.length} item(ns) fora do catálogo · <b>{pendentes}</b> pendente(s) de deliberação.
      </p>
      <div className="tabela-wrap">
        <table className="tabela">
          <thead>
            <tr>
              <th>Candidato</th>
              <th>Vaga</th>
              <th>Item declarado</th>
              <th>Pontos</th>
              <th>Deliberação</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {linhas.map((l) => (
              <LinhaItem key={l.curso_id} l={l} aberta={aberta === l.curso_id} alternar={() => setAberta(aberta === l.curso_id ? null : l.curso_id)} recarregar={() => setVersao((v) => v + 1)} />
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function LinhaItem({ l, aberta, alternar, recarregar }: { l: LinhaCurso; aberta: boolean; alternar: () => void; recarregar: () => void }) {
  return (
    <>
      <tr>
        <td>
          <strong>
            <Link href={`/painel/candidato/${l.inscricao_id}?aba=analise`}>{l.nome}</Link>
          </strong>
          <div>
            <small className="hint">{fmtCPF(l.cpf)}</small>
          </div>
        </td>
        <td>
          {l.grupo} · {l.nivel}
        </td>
        <td>
          {l.denominacao}
          <div className="hint">
            {l.tipo === "certificacao" ? "Certificação profissional" : `Curso, ${l.carga_horaria ?? "—"}h`} · concluído em {fmtData(l.data_conclusao)}
          </div>
        </td>
        <td>{l.pontos.toFixed(2).replace(".", ",")}</td>
        <td>
          {l.decisao ? (
            <span className={`pill ${l.decisao === "aceito" ? "pill-ok" : "pill-err"}`}>{l.decisao === "aceito" ? "Aceito" : "Recusado"}</span>
          ) : (
            <span className="pill pill-muted">Pendente</span>
          )}
        </td>
        <td style={{ textAlign: "right" }}>
          <button type="button" className="btn btn-sm" onClick={alternar}>
            {aberta ? "Fechar" : "Analisar"}
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

function PainelDecisao({ l, aoDecidir }: { l: LinhaCurso; aoDecidir: () => void }) {
  const [motivo, setMotivo] = useState("");
  const [erro, setErro] = useState("");
  const [salvando, setSalvando] = useState(false);

  async function decidir(decisao: "aceito" | "recusado") {
    setErro("");
    if (motivo.trim().length < 10) return setErro("Informe o motivo da decisão (mínimo de 10 caracteres).");
    setSalvando(true);
    const { error } = await createClient().schema("painel").rpc("decidir_curso_catalogo", { p_curso_id: l.curso_id, p_decisao: decisao, p_motivo: motivo });
    setSalvando(false);
    if (error) return setErro(error.message);
    setMotivo("");
    aoDecidir();
  }

  return (
    <div style={{ display: "grid", gap: 12, padding: "8px 0" }}>
      <div className="alert alert-ok" style={{ margin: 0 }}>
        <p>
          <b>{l.denominacao}</b> — {l.tipo === "certificacao" ? "certificação profissional" : `curso de ${l.carga_horaria ?? "—"}h`}, concluído em{" "}
          {fmtData(l.data_conclusao)}.
        </p>
        <p>
          Este item não consta no catálogo exemplificativo do Grupo {l.grupo} (Anexo I, item 2.1). Confira o conteúdo programático do certificado anexado na
          aba de Análise curricular do candidato e avalie a correlação direta com as atribuições do Grupo.
        </p>
      </div>

      {l.decisao ? (
        <div className="alert" style={{ margin: 0 }}>
          <p>
            <b>Última decisão: {l.decisao === "aceito" ? "aceito" : "recusado"}</b> por {l.decidido_por_nome} em {fmtDataHora(l.decidido_em)}.
          </p>
          <p>Motivo: {l.motivo}</p>
        </div>
      ) : null}

      <div className="field">
        <label htmlFor={`motivo-curso-${l.curso_id}`}>{l.decisao ? "Nova decisão (correção) — motivo" : "Motivo da decisão"} (obrigatório)</label>
        <textarea
          id={`motivo-curso-${l.curso_id}`}
          rows={3}
          value={motivo}
          onChange={(e) => setMotivo(e.target.value)}
          placeholder="Fundamente a decisão com base no conteúdo programático e nas atribuições do Grupo."
        />
      </div>
      {erro ? (
        <p className="err" role="alert">
          {erro}
        </p>
      ) : null}
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        <button type="button" className="btn btn-primary" disabled={salvando} onClick={() => decidir("aceito")}>
          Aceitar (pontua)
        </button>
        <button type="button" className="btn" disabled={salvando} onClick={() => decidir("recusado")}>
          Recusar (não pontua)
        </button>
      </div>
      <p className="hint" style={{ margin: 0 }}>
        A decisão fica registrada na auditoria, com autor e data. Uma nova decisão não apaga a anterior; a mais recente vale.
      </p>
    </div>
  );
}
