"use client";

import { useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export interface PublicacaoFinal {
  pontuacao: number | null;
  posicao: number | null;
  situacao: string;
  motivacao: string | null;
  publicado_em: string;
  publicado_por: string | null;
}

const fmt = (v: string) => new Date(v).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" });

// Publica (ou republica) o resultado final (Anexo IV, item 23): classificado na vaga imediata, cadastro de
// reserva (itens 2.1/11.1, minuta v11) ou eliminado na entrevista (item 6.5.7). Exige banca completa.
export function PublicarResultadoFinal({
  inscricaoId,
  nome,
  publicacao,
  aoPublicar,
}: {
  inscricaoId: string;
  nome: string;
  publicacao: PublicacaoFinal | null;
  aoPublicar: () => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const [justificativa, setJustificativa] = useState("");
  const [erro, setErro] = useState("");
  const [publicando, setPublicando] = useState(false);

  function abrir(e: React.MouseEvent) {
    e.stopPropagation();
    setErro("");
    ref.current?.showModal();
  }

  async function publicar() {
    setErro("");
    if (justificativa.trim().length < 5) return setErro("Informe a justificativa da publicação (mínimo de 5 caracteres).");
    setPublicando(true);
    const { error } = await createClient()
      .schema("painel")
      .rpc("publicar_resultado_final", { p_inscricao_id: inscricaoId, p_justificativa: justificativa.trim() });
    setPublicando(false);
    if (error) return setErro(error.message);
    setJustificativa("");
    aoPublicar();
  }

  return (
    <>
      <button type="button" className="btn btn-sm" onClick={abrir}>
        {publicacao ? "Republicar" : "Publicar resultado final"}
      </button>

      <dialog
        ref={ref}
        className="modal-motor"
        aria-labelledby={`publicar-final-titulo-${inscricaoId}`}
        onClick={(e) => {
          if (e.target === ref.current) ref.current?.close();
        }}
      >
        <div className="modal-motor-caixa">
          <header className="modal-motor-topo">
            <div>
              <h2 id={`publicar-final-titulo-${inscricaoId}`}>Publicar resultado final — {nome}</h2>
              <p className="hint" style={{ margin: 0 }}>
                Anexo IV, item 23. Vai para a área do candidato: pontuação (PF), posição, situação e motivação.
              </p>
            </div>
            <button type="button" className="btn btn-sm" onClick={() => ref.current?.close()} aria-label="Fechar">
              Fechar ✕
            </button>
          </header>

          <div className="modal-motor-corpo" style={{ display: "grid", gap: 16 }}>
            <div className="alert" style={{ margin: 0 }}>
              <p style={{ margin: 0 }}>
                <b>Situação atual:</b>{" "}
                {publicacao ? (
                  <>
                    publicado em {fmt(publicacao.publicado_em)} — {publicacao.situacao}
                    {publicacao.posicao ? `, ${publicacao.posicao}º lugar` : ""}
                    {publicacao.pontuacao !== null ? `, PF ${Number(publicacao.pontuacao).toFixed(1)}` : ""}.
                  </>
                ) : (
                  "ainda não publicado."
                )}
              </p>
            </div>

            <div className="field">
              <label htmlFor={`justificativa-final-${inscricaoId}`}>Justificativa da publicação (fica na auditoria) — obrigatória</label>
              <textarea
                id={`justificativa-final-${inscricaoId}`}
                rows={2}
                value={justificativa}
                onChange={(e) => setJustificativa(e.target.value)}
                placeholder="Ex.: Resultado final do Processo Seletivo, Anexo IV item 23."
              />
            </div>

            {erro ? (
              <p className="err" role="alert">
                {erro}
              </p>
            ) : null}

            <div style={{ display: "flex", gap: 8 }}>
              <button type="button" className="btn btn-primary" disabled={publicando} onClick={() => void publicar()}>
                {publicando ? <span className="spin" aria-hidden /> : null} {publicacao ? "Republicar" : "Publicar"}
              </button>
            </div>
            <p className="hint" style={{ margin: 0 }}>
              Só funciona com a banca completa (3 fichas) ou nota da entrevista abaixo de 15 pontos (eliminação, item 6.5.7). Republicar atualiza o mesmo
              resultado, não duplica.
            </p>
          </div>
        </div>
      </dialog>
    </>
  );
}
