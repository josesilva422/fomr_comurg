"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export interface PresencaRegistro {
  situacao: "realizada" | "nao_compareceu";
  observacao: string | null;
  registrado_por_nome: string;
  registrado_em: string;
}

const fmtData = (iso: string) => new Date(iso).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });

const MENSAGENS: Record<string, string> = {
  sem_convite: "Registre o convite da entrevista antes de informar a presença.",
  nao_convocado: "Só candidatos convocados para a entrevista têm presença registrada.",
  ja_tem_ficha: "Este candidato já tem ficha de avaliador; não é possível registrar ausência.",
};

// Presença na entrevista técnica: "Entrevista realizada" (a situação do candidato vira "Em avaliação pela banca") ou
// "Candidato não compareceu" (eliminado pelo item 6.5.7). Decisão da Comissão, com autor e data; corrigir gera novo registro.
export function PresencaEntrevista({
  inscricaoId,
  historico,
  aoMudar,
}: {
  inscricaoId: string;
  historico: PresencaRegistro[];
  aoMudar: () => void;
}) {
  const [observacao, setObservacao] = useState("");
  const [confirmando, setConfirmando] = useState(false);
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState("");
  const atual = historico[0] ?? null;

  async function registrar(situacao: "realizada" | "nao_compareceu") {
    setErro("");
    setSalvando(true);
    const { error } = await createClient()
      .schema("painel")
      .rpc("registrar_presenca_entrevista", { p_inscricao_id: inscricaoId, p_situacao: situacao, p_observacao: observacao.trim() || null });
    setSalvando(false);
    if (error) {
      const dica = (error as { hint?: string }).hint ?? "";
      return setErro(MENSAGENS[dica] ?? error.message);
    }
    setObservacao("");
    setConfirmando(false);
    aoMudar();
  }

  return (
    <div className="card" style={{ margin: "16px 0", padding: 16 }}>
      <h4 style={{ margin: 0 }}>Presença na entrevista</h4>

      {atual ? (
        <div className={`alert ${atual.situacao === "nao_compareceu" ? "alert-err" : "alert-ok"}`} style={{ marginTop: 10 }}>
          <p>
            {atual.situacao === "nao_compareceu" ? (
              <>
                <b>Candidato não compareceu à entrevista técnica.</b> Eliminado nos termos do item 6.5.7 do edital.
              </>
            ) : (
              <>
                <b>Entrevista realizada.</b> Situação do candidato: em avaliação pela banca.
              </>
            )}
            <br />
            <small>
              Registrado por {atual.registrado_por_nome} em {fmtData(atual.registrado_em)}
              {atual.observacao ? ` — ${atual.observacao}` : ""}
            </small>
          </p>
        </div>
      ) : (
        <p className="hint">Ainda não informada. Depois da data da entrevista, registre se ela foi realizada ou se o candidato não compareceu.</p>
      )}

      <div className="field" style={{ marginTop: 10 }}>
        <label htmlFor={`pres-obs-${inscricaoId}`}>Observação (opcional)</label>
        <input
          id={`pres-obs-${inscricaoId}`}
          value={observacao}
          onChange={(e) => setObservacao(e.target.value)}
          maxLength={500}
          placeholder="Ex.: não entrou na sala em 15 minutos"
        />
      </div>

      {erro ? (
        <p className="err" role="alert">
          {erro}
        </p>
      ) : null}

      {confirmando ? (
        <div className="alert alert-warn" style={{ flexDirection: "column", gap: 8 }}>
          <p>
            <b>Confirmar que o candidato não compareceu?</b> Ele será eliminado pelo item 6.5.7 do edital, e o candidato verá isso no portal. Se foi engano, dá
            para corrigir depois com um novo registro (o histórico é mantido).
          </p>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button type="button" className="btn btn-primary" disabled={salvando} onClick={() => void registrar("nao_compareceu")}>
              Sim, não compareceu
            </button>
            <button type="button" className="btn" disabled={salvando} onClick={() => setConfirmando(false)}>
              Cancelar
            </button>
          </div>
        </div>
      ) : (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 8 }}>
          <button type="button" className="btn btn-primary" disabled={salvando} onClick={() => void registrar("realizada")}>
            Entrevista realizada
          </button>
          <button type="button" className="btn" disabled={salvando} onClick={() => setConfirmando(true)}>
            Candidato não compareceu
          </button>
        </div>
      )}

      {historico.length > 1 ? (
        <details style={{ marginTop: 10 }}>
          <summary className="hint" style={{ cursor: "pointer" }}>
            Histórico de registros ({historico.length})
          </summary>
          <ul style={{ margin: "6px 0 0", paddingLeft: 18 }}>
            {historico.map((h) => (
              <li key={h.registrado_em}>
                {h.situacao === "nao_compareceu" ? "Não compareceu" : "Realizada"} — {h.registrado_por_nome}, {fmtData(h.registrado_em)}
                {h.observacao ? ` (${h.observacao})` : ""}
              </li>
            ))}
          </ul>
        </details>
      ) : null}
    </div>
  );
}
