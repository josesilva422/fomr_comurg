"use client";

import { useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export interface PublicacaoAC {
  etapa: "ac_preliminar" | "ac_definitivo";
  pontuacao: number | null;
  posicao: number | null;
  situacao: string;
  motivacao: string | null;
  publicado_em: string;
  publicado_por: string | null;
}

const fmt = (v: string) => new Date(v).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" });

// Publica (ou republica) o resultado da análise curricular de um candidato homologado, nas duas etapas do
// Anexo IV: item 14 (preliminar) e item 17 (definitivo + convocação, itens 6.4.4/6.5.1). Edital 7.3, 13.2, 13.3;
// CLAUDE.md seção 6 — o que vai para publico.resultados_candidato é só pontuação, posição, situação e motivação.
export function PublicarResultado({
  inscricaoId,
  nome,
  preliminar,
  definitivo,
  aoPublicar,
}: {
  inscricaoId: string;
  nome: string;
  preliminar: PublicacaoAC | null;
  definitivo: PublicacaoAC | null;
  aoPublicar: () => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const [justificativa, setJustificativa] = useState("");
  const [erro, setErro] = useState("");
  const [publicando, setPublicando] = useState<"ac_preliminar" | "ac_definitivo" | null>(null);

  function abrir(e: React.MouseEvent) {
    e.stopPropagation();
    setErro("");
    ref.current?.showModal();
  }

  async function publicar(etapa: "ac_preliminar" | "ac_definitivo") {
    setErro("");
    if (justificativa.trim().length < 5) return setErro("Informe a justificativa da publicação (mínimo de 5 caracteres).");
    setPublicando(etapa);
    const { error } = await createClient()
      .schema("painel")
      .rpc("publicar_resultado_ac", { p_inscricao_id: inscricaoId, p_etapa: etapa, p_justificativa: justificativa.trim() });
    setPublicando(null);
    if (error) return setErro(error.message);
    setJustificativa("");
    aoPublicar();
  }

  return (
    <>
      <button type="button" className="btn btn-sm" onClick={abrir}>
        Publicar resultado
      </button>

      <dialog
        ref={ref}
        className="modal-motor"
        aria-labelledby={`publicar-titulo-${inscricaoId}`}
        onClick={(e) => {
          if (e.target === ref.current) ref.current?.close();
        }}
      >
        <div className="modal-motor-caixa">
          <header className="modal-motor-topo">
            <div>
              <h2 id={`publicar-titulo-${inscricaoId}`}>Publicar resultado — {nome}</h2>
              <p className="hint" style={{ margin: 0 }}>
                Vai para a área do candidato: pontuação, posição, situação e motivação (edital 7.3, 13.2, 13.3). Nada mais do que isso é exposto.
              </p>
            </div>
            <button type="button" className="btn btn-sm" onClick={() => ref.current?.close()} aria-label="Fechar">
              Fechar ✕
            </button>
          </header>

          <div className="modal-motor-corpo" style={{ display: "grid", gap: 16 }}>
            <div className="alert" style={{ margin: 0 }}>
              <p>
                <b>Resultado preliminar (Anexo IV, item 14):</b>{" "}
                {preliminar ? (
                  <>
                    publicado em {fmt(preliminar.publicado_em)} — {preliminar.situacao}
                    {preliminar.posicao ? `, ${preliminar.posicao}º lugar` : ""}
                    {preliminar.pontuacao !== null ? `, ${Number(preliminar.pontuacao).toFixed(1)} pts` : ""}.
                  </>
                ) : (
                  "ainda não publicado."
                )}
              </p>
              <p style={{ margin: 0 }}>
                <b>Resultado definitivo + convocação (item 17):</b>{" "}
                {definitivo ? (
                  <>
                    publicado em {fmt(definitivo.publicado_em)} — {definitivo.situacao}
                    {definitivo.posicao ? `, ${definitivo.posicao}º lugar` : ""}.
                  </>
                ) : (
                  "ainda não publicado."
                )}
              </p>
            </div>

            <div className="field">
              <label htmlFor={`justificativa-${inscricaoId}`}>Justificativa da publicação (fica na auditoria) — obrigatória</label>
              <textarea
                id={`justificativa-${inscricaoId}`}
                rows={2}
                value={justificativa}
                onChange={(e) => setJustificativa(e.target.value)}
                placeholder="Ex.: Resultado preliminar da análise curricular, Anexo IV item 14."
              />
            </div>

            {erro ? (
              <p className="err" role="alert">
                {erro}
              </p>
            ) : null}

            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              <button type="button" className="btn btn-primary" disabled={publicando !== null} onClick={() => void publicar("ac_preliminar")}>
                {publicando === "ac_preliminar" ? <span className="spin" aria-hidden /> : null}{" "}
                {preliminar ? "Republicar resultado preliminar" : "Publicar resultado preliminar"}
              </button>
              <button type="button" className="btn" disabled={publicando !== null} onClick={() => void publicar("ac_definitivo")}>
                {publicando === "ac_definitivo" ? <span className="spin" aria-hidden /> : null}{" "}
                {definitivo ? "Republicar resultado definitivo" : "Publicar resultado definitivo"}
              </button>
            </div>
            <p className="hint" style={{ margin: 0 }}>
              Só funciona com a inscrição já homologada (Anexo IV, item 10). Republicar (ex.: após julgamento de recurso) atualiza o mesmo resultado, não
              duplica.
            </p>
          </div>
        </div>
      </dialog>
    </>
  );
}
