"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import type { Grupo, Nivel } from "@/lib/tipos";
import { BANCA_MINIMA, fmtNota, type LinhaClassificacao } from "@/lib/entrevista";
import { PublicarResultadoFinal, type PublicacaoFinal } from "./PublicarResultadoFinal";

const fmtCPF = (v: string) => v.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4");

// Classificação por Grupo e Nível: PF = AC + ET, com os desempates do item 7.2 calculados no banco.
// Só entram os candidatos convocados para a entrevista. É um RASCUNHO da Comissão (nada é publicado ao candidato).
export function ClassificacaoTabela() {
  const router = useRouter();
  const [grupo, setGrupo] = useState<Grupo | "">("");
  const [nivel, setNivel] = useState<Nivel | "">("");
  const chave = `${grupo}|${nivel}`;
  const [res, setRes] = useState<{ chave: string; linhas: LinhaClassificacao[]; erro: string } | null>(null);
  const [publicacoes, setPublicacoes] = useState<Record<string, PublicacaoFinal>>({});
  const [versaoPublicacoes, setVersaoPublicacoes] = useState(0);

  useEffect(() => {
    let vivo = true;
    createClient()
      .schema("painel")
      .rpc("classificacao_final", { p_grupo: grupo || null, p_nivel: nivel || null })
      .then(({ data, error }: { data: LinhaClassificacao[] | null; error: { message: string } | null }) => {
        if (vivo) setRes({ chave, linhas: data ?? [], erro: error?.message ?? "" });
      });
    return () => {
      vivo = false;
    };
  }, [grupo, nivel, chave]);

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("publicacoes_final")
      .then(({ data }: { data: (PublicacaoFinal & { inscricao_id: string })[] | null }) =>
        setPublicacoes(Object.fromEntries((data ?? []).map((r) => [r.inscricao_id, r]))),
      );
  }, [versaoPublicacoes]);

  const carregando = !res || res.chave !== chave;
  const erro = res && res.chave === chave ? res.erro : "";
  const linhas = res && res.chave === chave && !res.erro ? res.linhas : null;

  return (
    <div>
      <div className="filtros-avancados" style={{ marginBottom: 16 }}>
        <select value={grupo} onChange={(e) => setGrupo(e.target.value as Grupo | "")} aria-label="Grupo">
          <option value="">Todos os grupos</option>
          {(Object.keys(GRUPOS) as Grupo[]).map((g) => (
            <option key={g} value={g}>
              {GRUPOS[g].nome}
            </option>
          ))}
        </select>
        <select value={nivel} onChange={(e) => setNivel(e.target.value as Nivel | "")} aria-label="Nível">
          <option value="">Todos os níveis</option>
          {(Object.keys(NIVEIS) as Nivel[]).map((n) => (
            <option key={n} value={n}>
              {NIVEIS[n].nome}
            </option>
          ))}
        </select>
      </div>

      {erro ? (
        <div className="alert alert-err">
          <p>{erro}</p>
        </div>
      ) : carregando || linhas === null ? (
        <p className="hint">Carregando…</p>
      ) : linhas.length === 0 ? (
        <div className="empty">Nenhum candidato convocado para a entrevista com esses filtros.</div>
      ) : (
        <div className="tabela-wrap">
          <table className="tabela">
            <thead>
              <tr>
                <th>Grupo · Nível</th>
                <th>Pos.</th>
                <th>Candidato</th>
                <th style={{ textAlign: "right" }}>AC (60)</th>
                <th style={{ textAlign: "right" }}>ET (40)</th>
                <th style={{ textAlign: "right" }}>PF (100)</th>
                <th>Situação</th>
                <th>Publicação ao candidato</th>
              </tr>
            </thead>
            <tbody>
              {linhas.map((l) => (
                <tr key={l.inscricao_id} onClick={() => router.push(`/painel/candidato/${l.inscricao_id}?aba=entrevista`)} tabIndex={0}>
                  <td>
                    {GRUPOS[l.grupo].nome} · {NIVEIS[l.nivel].nome}
                  </td>
                  <td>{l.posicao ? `${l.posicao}º` : "—"}</td>
                  <td>
                    <strong>{l.nome}</strong>
                    <br />
                    <small className="hint">{fmtCPF(l.cpf)}</small>
                  </td>
                  <td style={{ textAlign: "right" }}>{fmtNota(l.ac)}</td>
                  <td style={{ textAlign: "right" }}>{fmtNota(l.et)}</td>
                  <td className="col-total" style={{ textAlign: "right" }}>
                    {fmtNota(l.pf)}
                  </td>
                  <td>
                    {l.n_fichas === 0 ? (
                      <span className="pill pill-muted">Sem fichas</span>
                    ) : l.abaixo_do_corte ? (
                      <span className="pill pill-err">Abaixo de 15 pts (6.5.7)</span>
                    ) : !l.banca_completa ? (
                      <span className="pill pill-muted">Aguardando fichas ({l.n_fichas} de {BANCA_MINIMA})</span>
                    ) : l.posicao && l.posicao <= l.vagas ? (
                      <span className="pill pill-ok">Classificado ({l.posicao}º)</span>
                    ) : l.posicao ? (
                      <span className="pill pill-ok">Cadastro de reserva ({l.posicao}º)</span>
                    ) : (
                      <span className="pill pill-muted">Não classificado</span>
                    )}
                  </td>
                  <td onClick={(e) => e.stopPropagation()}>
                    {l.abaixo_do_corte || l.banca_completa ? (
                      <div style={{ display: "grid", gap: 6, justifyItems: "start" }}>
                        {publicacoes[l.inscricao_id] ? <small className="hint">Publicado: {publicacoes[l.inscricao_id].situacao}</small> : null}
                        <PublicarResultadoFinal
                          inscricaoId={l.inscricao_id}
                          nome={l.nome}
                          publicacao={publicacoes[l.inscricao_id] ?? null}
                          aoPublicar={() => setVersaoPublicacoes((v) => v + 1)}
                        />
                      </div>
                    ) : (
                      <small className="hint">Aguardando banca</small>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <p className="hint" style={{ marginTop: 12 }}>
        Desempate (item 7.2), nesta ordem: idade ≥ 60 anos (o mais velho), maior nota na entrevista, maior pontuação em experiência, maior total da AC,
        graduação mais antiga e maior idade. A idade é contada na data de encerramento das inscrições (convenção a confirmar). Abaixo de 15 pontos
        na entrevista o edital prevê eliminação — o sistema só sinaliza; a decisão é da Comissão.
      </p>
    </div>
  );
}
