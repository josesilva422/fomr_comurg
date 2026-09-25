"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { BANCA_MINIMA, COMPETENCIAS, CORTE_ENTREVISTA, TOTAL_ENTREVISTA, fmtNota, type EntrevistaDoCandidato } from "@/lib/entrevista";
import { FichaAvaliador } from "../../entrevista/FichaAvaliador";

const fmtData = (iso: string) => new Date(iso).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });

// Entrevista técnica de um candidato: visão GERAL (quantas fichas, quem já enviou, média só com 3+) e a ficha do
// PRÓPRIO avaliador logado. Fichas cegas: a nota de cada avaliador nunca aparece para outra pessoa (edital 6.5.5).
export function EntrevistaSecao({ inscricaoId }: { inscricaoId: string }) {
  const [dados, setDados] = useState<EntrevistaDoCandidato | null>(null);
  const [erro, setErro] = useState("");
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let vivo = true;
    createClient()
      .schema("painel")
      .rpc("entrevista_do_candidato", { p_inscricao_id: inscricaoId })
      .then(({ data, error }: { data: EntrevistaDoCandidato | null; error: { message: string } | null }) => {
        if (!vivo) return;
        if (error) setErro(error.message);
        else setDados(data);
      });
    return () => {
      vivo = false;
    };
  }, [inscricaoId, tick]);

  if (!dados) {
    return erro ? (
      <div className="alert alert-err">
        <p>{erro}</p>
      </div>
    ) : (
      <p className="hint">Carregando entrevista…</p>
    );
  }

  if (!dados.convocado) {
    return (
      <div>
        <h3>Entrevista técnica</h3>
        <p className="hint">
          Este candidato não está convocado para a entrevista (exige habilitação, AC ≥ 35 pontos e estar entre os 3 melhores por vaga — itens 6.4.4 e 6.5.1).
        </p>
      </div>
    );
  }

  const faltam = Math.max(dados.minimo_fichas - dados.n_fichas, 0);

  return (
    <div>
      <h3>Entrevista técnica</h3>
      <p className="hint">
        Cada avaliador envia a própria ficha (Anexo II): nota inteira por competência e justificativa obrigatória. Ninguém vê a nota de outro avaliador.
        A partir de {BANCA_MINIMA} fichas aparece a <b>média</b> das fichas enviadas, que é a nota da entrevista (ET, item 6.5.5). Máximo de{" "}
        {dados.maximo_fichas} fichas por candidato.
      </p>

      <div className="tabela-wrap" style={{ margin: "12px 0" }}>
        <table className="tabela">
          <thead>
            <tr>
              <th>AC (máx. 60)</th>
              <th>Entrevista — ET (máx. {TOTAL_ENTREVISTA})</th>
              <th>PF = AC + ET (máx. 100)</th>
              <th>Fichas enviadas</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td className="col-total">{fmtNota(dados.ac)}</td>
              <td className="col-total">{dados.media_liberada ? fmtNota(dados.et) : "—"}</td>
              <td className="col-total">{dados.media_liberada ? fmtNota(dados.pf) : "—"}</td>
              <td>
                {dados.n_fichas} de {dados.maximo_fichas}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      {!dados.media_liberada ? (
        <div className="alert alert-info">
          <p>
            {dados.n_fichas === 0
              ? `Nenhuma ficha enviada. A média aparece quando houver ${BANCA_MINIMA} fichas.`
              : `Faltam ${faltam} ficha${faltam > 1 ? "s" : ""} para aparecer a média. Até lá, nenhuma nota é mostrada.`}
          </p>
        </div>
      ) : null}
      {dados.abaixo_do_corte ? (
        <div className="alert alert-err">
          <p>
            Média da entrevista abaixo de {CORTE_ENTREVISTA} pontos (item 6.5.7): o edital prevê eliminação. O sistema só sinaliza — a decisão e a
            motivação são da Comissão.
          </p>
        </div>
      ) : null}

      {dados.media_liberada && dados.media_por_competencia ? (
        <div className="tabela-wrap" style={{ margin: "12px 0" }}>
          <table className="tabela">
            <thead>
              <tr>
                <th>Competência</th>
                <th style={{ textAlign: "right" }}>Média das fichas</th>
              </tr>
            </thead>
            <tbody>
              {COMPETENCIAS.map((c) => (
                <tr key={c.chave}>
                  <td>{c.rotulo}</td>
                  <td style={{ textAlign: "right" }}>
                    {fmtNota(dados.media_por_competencia![c.chave])} / {c.peso}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}

      {dados.avaliadores.length > 0 ? (
        <p className="hint">
          <b>Fichas enviadas por:</b> {dados.avaliadores.map((a) => `${a.nome} (${fmtData(a.enviada_em)})`).join(" · ")}
        </p>
      ) : null}

      <FichaAvaliador
        key={dados.minha_ficha?.updated_at ?? "nova"}
        inscricaoId={inscricaoId}
        minhaFicha={dados.minha_ficha}
        limiteAtingido={dados.n_fichas >= dados.maximo_fichas}
        aoSalvar={() => setTick((t) => t + 1)}
      />
    </div>
  );
}
