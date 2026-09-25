"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import { BANCA_MINIMA, MAXIMO_FICHAS, TOTAL_ENTREVISTA, type EntrevistaDoCandidato, type MinhaEntrevista } from "@/lib/entrevista";
import { FichaAvaliador } from "../entrevista/FichaAvaliador";

// Página do AVALIADOR: candidatos convocados e a situação da própria ficha em cada um. Abrir um candidato mostra só a
// ficha de quem está logado (nunca a de outro avaliador).
export function MinhasFichas() {
  const [linhas, setLinhas] = useState<MinhaEntrevista[] | null>(null);
  const [erro, setErro] = useState("");
  const [aberta, setAberta] = useState<string | null>(null);
  const [detalhe, setDetalhe] = useState<EntrevistaDoCandidato | null>(null);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let vivo = true;
    createClient()
      .schema("painel")
      .rpc("minhas_entrevistas")
      .then(({ data, error }: { data: MinhaEntrevista[] | null; error: { message: string } | null }) => {
        if (!vivo) return;
        if (error) setErro(error.message);
        else setLinhas(data ?? []);
      });
    return () => {
      vivo = false;
    };
  }, [tick]);

  useEffect(() => {
    if (!aberta) return;
    let vivo = true;
    createClient()
      .schema("painel")
      .rpc("entrevista_do_candidato", { p_inscricao_id: aberta })
      .then(({ data, error }: { data: EntrevistaDoCandidato | null; error: { message: string } | null }) => {
        if (!vivo) return;
        if (error) setErro(error.message);
        else setDetalhe(data);
      });
    return () => {
      vivo = false;
    };
  }, [aberta, tick]);

  function abrir(id: string) {
    setDetalhe(null);
    setAberta(aberta === id ? null : id);
  }

  if (erro) {
    return (
      <div className="alert alert-err">
        <p>{erro}</p>
      </div>
    );
  }
  if (!linhas) return <p className="hint">Carregando…</p>;
  if (linhas.length === 0) return <div className="empty">Nenhum candidato convocado para a entrevista.</div>;

  const pendentes = linhas.filter((l) => l.minha_ficha_total === null).length;

  return (
    <div>
      <p className="hint" style={{ marginBottom: 12 }}>
        {pendentes === 0 ? "Você já enviou ficha para todos os convocados." : `Você ainda não enviou ficha para ${pendentes} candidato${pendentes > 1 ? "s" : ""}.`}
      </p>
      <div className="tabela-wrap">
        <table className="tabela">
          <thead>
            <tr>
              <th>Grupo · Nível</th>
              <th>Candidato</th>
              <th>Minha ficha</th>
              <th>Fichas da banca</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {linhas.map((l) => (
              <tr key={l.inscricao_id}>
                <td>
                  {GRUPOS[l.grupo].nome} · {NIVEIS[l.nivel].nome}
                </td>
                <td>
                  <Link href={`/painel/candidato/${l.inscricao_id}?aba=entrevista`}>
                    <strong>{l.nome}</strong>
                  </Link>
                </td>
                <td>
                  {l.minha_ficha_total === null ? (
                    <span className="pill pill-muted">Pendente</span>
                  ) : (
                    <span className="pill pill-ok">
                      Enviada — {l.minha_ficha_total}/{TOTAL_ENTREVISTA}
                    </span>
                  )}
                </td>
                <td>
                  {l.n_fichas} de {MAXIMO_FICHAS}
                  {l.media_liberada ? <small className="hint"> · média liberada</small> : <small className="hint"> · média com {BANCA_MINIMA}</small>}
                </td>
                <td>
                  <button type="button" className="btn btn-sm" onClick={() => abrir(l.inscricao_id)}>
                    {aberta === l.inscricao_id ? "Fechar" : l.minha_ficha_total === null ? "Preencher" : "Corrigir"}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {aberta ? (
        detalhe ? (
          <div style={{ marginTop: 16 }}>
            <h3 style={{ marginBottom: 0 }}>{linhas.find((l) => l.inscricao_id === aberta)?.nome}</h3>
            <FichaAvaliador
              key={`${aberta}-${detalhe.minha_ficha?.updated_at ?? "nova"}`}
              inscricaoId={aberta}
              minhaFicha={detalhe.minha_ficha}
              limiteAtingido={detalhe.n_fichas >= detalhe.maximo_fichas}
              aoSalvar={() => setTick((t) => t + 1)}
            />
          </div>
        ) : (
          <p className="hint" style={{ marginTop: 16 }}>
            Carregando ficha…
          </p>
        )
      ) : null}
    </div>
  );
}
