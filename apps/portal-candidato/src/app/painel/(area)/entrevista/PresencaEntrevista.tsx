"use client";

import { useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { dataPorExtenso } from "@/lib/convite-entrevista";

export interface PresencaRegistro {
  situacao: "realizada" | "nao_compareceu";
  observacao: string | null;
  link_gravacao: string | null;
  registrado_por_nome: string;
  registrado_em: string;
}

export interface Finalizacao {
  finalizado_em: string;
  finalizado_por_nome: string;
}

const fmtData = (iso: string) => new Date(iso).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });

const MENSAGENS: Record<string, string> = {
  sem_convite: "Registre o convite da entrevista antes de informar a presença.",
  nao_convocado: "Só candidatos convocados para a entrevista têm presença registrada.",
  ja_tem_ficha: "Este candidato já tem ficha de avaliador; não é possível registrar ausência.",
  link_invalido: "O link da gravação precisa começar com http:// ou https://.",
  motivo_obrigatorio: "Informe o motivo do não comparecimento (mínimo de 5 caracteres).",
  entrevista_finalizada: "O registro deste candidato já foi finalizado.",
  faltam_fichas: "A banca precisa ter lançado pelo menos 3 fichas (item 6.5.2) para finalizar.",
  sem_presenca: "Registre que o candidato compareceu antes de finalizar.",
};

type Situacao = "realizada" | "nao_compareceu";

// "Presença" (abaixo do convite): botões "Compareceu" e "Não compareceu", cada um abre um pop-up com observação e o link da
// gravação da reunião (ficam salvos só para a Comissão; o candidato não vê). Com 3 fichas da banca, aparece "Finalizar registro
// do candidato". "Não compareceu" = eliminado pelo item 6.5.7.
export function PresencaEntrevista({
  inscricaoId,
  nome,
  convite,
  historico,
  finalizacao,
  nFichas,
  aoMudar,
}: {
  inscricaoId: string;
  nome: string;
  /** Convite vigente (data e horário da entrevista agendada), usado na confirmação do não comparecimento. */
  convite: { data: string; horario: string } | null;
  historico: PresencaRegistro[];
  finalizacao: Finalizacao | null;
  nFichas: number;
  aoMudar: () => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const [alvo, setAlvo] = useState<Situacao>("realizada");
  const [observacao, setObservacao] = useState("");
  const [link, setLink] = useState("");
  const [salvando, setSalvando] = useState(false);
  const [etapa, setEtapa] = useState<"form" | "confirmar">("form");
  const [erro, setErro] = useState("");
  const [confirmandoFim, setConfirmandoFim] = useState(false);
  const [erroFim, setErroFim] = useState("");
  const atual = historico[0] ?? null;
  const finalizado = finalizacao !== null;
  const podeFinalizar = !finalizado && atual?.situacao === "realizada" && nFichas >= 3;

  function abrir(s: Situacao) {
    setAlvo(s);
    setObservacao("");
    setLink("");
    setErro("");
    setEtapa("form");
    ref.current?.showModal();
  }

  // "Compareceu" salva direto. "Não compareceu" exige o motivo e passa por uma segunda confirmação antes de salvar.
  function continuar() {
    setErro("");
    if (alvo === "nao_compareceu") {
      if (observacao.trim().length < 5) return setErro(MENSAGENS.motivo_obrigatorio);
      return setEtapa("confirmar");
    }
    void salvar();
  }

  async function salvar() {
    setErro("");
    setSalvando(true);
    const { error } = await createClient()
      .schema("painel")
      .rpc("registrar_presenca_entrevista", {
        p_inscricao_id: inscricaoId,
        p_situacao: alvo,
        p_observacao: observacao.trim() || null,
        p_link_gravacao: link.trim() || null,
      });
    setSalvando(false);
    if (error) {
      const dica = (error as { hint?: string }).hint ?? "";
      setEtapa("form");
      return setErro(MENSAGENS[dica] ?? error.message);
    }
    ref.current?.close();
    aoMudar();
  }

  async function finalizar() {
    setErroFim("");
    setSalvando(true);
    const { error } = await createClient().schema("painel").rpc("finalizar_entrevista", { p_inscricao_id: inscricaoId });
    setSalvando(false);
    if (error) {
      const dica = (error as { hint?: string }).hint ?? "";
      return setErroFim(MENSAGENS[dica] ?? error.message);
    }
    setConfirmandoFim(false);
    aoMudar();
  }

  return (
    <div style={{ marginTop: 14, paddingTop: 12, borderTop: "1px solid var(--line)", display: "flex", flexDirection: "column", alignItems: "flex-end", textAlign: "right" }}>
      <p style={{ margin: 0, fontWeight: 700, fontSize: 14 }}>Presença</p>

      {atual ? (
        <p className="hint" style={{ margin: "4px 0 0" }}>
          {atual.situacao === "nao_compareceu" ? "Não compareceu (eliminado pelo item 6.5.7)" : "Compareceu"} — {atual.registrado_por_nome},{" "}
          {fmtData(atual.registrado_em)}
          {atual.observacao ? ` · Obs.: ${atual.observacao}` : ""}
          {atual.link_gravacao ? (
            <>
              {" "}
              ·{" "}
              <a href={atual.link_gravacao} target="_blank" rel="noopener noreferrer">
                gravação
              </a>
            </>
          ) : null}
        </p>
      ) : (
        <p className="hint" style={{ margin: "4px 0 0" }}>
          Depois da entrevista, informe se o candidato compareceu.
        </p>
      )}

      {!finalizado ? (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", justifyContent: "flex-end", marginTop: 8 }}>
          <button type="button" className="btn btn-sm btn-sucesso" onClick={() => abrir("realizada")}>
            Compareceu
          </button>
          <button type="button" className="btn btn-sm btn-perigo" onClick={() => abrir("nao_compareceu")}>
            Não compareceu
          </button>
        </div>
      ) : null}

      {podeFinalizar ? (
        <div style={{ marginTop: 10, display: "flex", flexDirection: "column", alignItems: "flex-end" }}>
          {confirmandoFim ? (
            <div className="alert alert-warn" style={{ flexDirection: "column", gap: 8, margin: 0, textAlign: "left" }}>
              <p>
                <b>Finalizar o registro de {nome}?</b> As informações ficam salvas, a situação do candidato passa a &quot;Avaliação técnica finalizada&quot; e não
                será mais possível alterar a presença nem as fichas.
              </p>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                <button type="button" className="btn btn-primary btn-sm" disabled={salvando} onClick={() => void finalizar()}>
                  Sim, finalizar
                </button>
                <button type="button" className="btn btn-sm" disabled={salvando} onClick={() => setConfirmandoFim(false)}>
                  Cancelar
                </button>
              </div>
            </div>
          ) : (
            <button type="button" className="btn btn-primary btn-sm" onClick={() => setConfirmandoFim(true)}>
              Finalizar registro do candidato
            </button>
          )}
          {erroFim ? (
            <p className="err" role="alert">
              {erroFim}
            </p>
          ) : null}
        </div>
      ) : null}

      {finalizado ? (
        <p className="hint" style={{ margin: "8px 0 0" }}>
          <b>Registro finalizado</b> por {finalizacao.finalizado_por_nome} em {fmtData(finalizacao.finalizado_em)}.
        </p>
      ) : atual?.situacao === "realizada" && nFichas < 3 ? (
        <p className="hint" style={{ margin: "8px 0 0" }}>
          O botão &quot;Finalizar registro do candidato&quot; aparece depois das 3 fichas da banca ({nFichas} de 3).
        </p>
      ) : null}

      {historico.length > 1 ? (
        <details style={{ marginTop: 8 }}>
          <summary className="hint" style={{ cursor: "pointer" }}>
            Histórico de registros ({historico.length})
          </summary>
          <ul style={{ margin: "6px 0 0", paddingLeft: 18 }}>
            {historico.map((h) => (
              <li key={h.registrado_em}>
                {h.situacao === "nao_compareceu" ? "Não compareceu" : "Compareceu"} — {h.registrado_por_nome}, {fmtData(h.registrado_em)}
                {h.observacao ? ` (${h.observacao})` : ""}
              </li>
            ))}
          </ul>
        </details>
      ) : null}

      <dialog
        ref={ref}
        className="modal-motor"
        aria-labelledby={`pres-titulo-${inscricaoId}`}
        onClick={(e) => {
          e.stopPropagation();
          if (e.target === ref.current) ref.current?.close();
        }}
        onKeyDown={(e) => e.stopPropagation()}
      >
        <div className="modal-motor-caixa" style={{ width: "min(560px, 100%)", textAlign: "left" }}>
          <header className="modal-motor-topo">
            <div>
              <h2 id={`pres-titulo-${inscricaoId}`}>{alvo === "nao_compareceu" ? "Candidato não compareceu" : "Candidato compareceu"}</h2>
              <p className="hint" style={{ margin: 0 }}>
                {nome} · a observação e o link ficam salvos só para a Comissão; o candidato não os vê.
              </p>
            </div>
            <button type="button" className="btn btn-sm btn-ghost" onClick={() => ref.current?.close()} aria-label="Fechar">
              ✕
            </button>
          </header>
          <div className="modal-motor-corpo">
            {etapa === "confirmar" ? (
              <div style={{ display: "grid", gap: 14 }}>
                <div className="alert alert-err" style={{ margin: 0, flexDirection: "column", gap: 0 }}>
                  <p>
                    Deseja confirmar o <b>não comparecimento</b> do candidato <b>{nome}</b> na entrevista técnica
                    {convite ? (
                      <>
                        {" "}
                        agendada para <b>{dataPorExtenso(convite.data)}</b>, às <b>{convite.horario}</b>
                      </>
                    ) : null}
                    ?
                  </p>
                  <p>
                    Motivo informado: <i>{observacao.trim()}</i>
                  </p>
                  <p>O candidato será eliminado pelo item 6.5.7 do edital e verá isso no portal.</p>
                </div>
                {erro ? (
                  <p className="err" role="alert">
                    {erro}
                  </p>
                ) : null}
                <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", flexWrap: "wrap" }}>
                  <button type="button" className="btn" disabled={salvando} onClick={() => setEtapa("form")}>
                    Voltar
                  </button>
                  <button type="button" className="btn btn-perigo" disabled={salvando} onClick={() => void salvar()}>
                    {salvando ? <span className="spin" aria-hidden /> : null} Sim, confirmar não comparecimento
                  </button>
                </div>
              </div>
            ) : (
              <>
                {alvo === "nao_compareceu" ? (
                  <div className="alert alert-warn" style={{ margin: "0 0 12px" }}>
                    <p>
                      Ao salvar, o candidato é <b>eliminado pelo item 6.5.7</b> do edital e vê isso no portal. Você ainda confirma na próxima etapa.
                    </p>
                  </div>
                ) : null}
                <div className="field">
                  <label htmlFor={`pres-obs-${inscricaoId}`}>
                    {alvo === "nao_compareceu" ? (
                      <>
                        Motivo do não comparecimento{" "}
                        <b className="req" aria-hidden="true">
                          *
                        </b>
                      </>
                    ) : (
                      "Observação"
                    )}
                  </label>
                  <textarea
                    id={`pres-obs-${inscricaoId}`}
                    rows={3}
                    value={observacao}
                    onChange={(e) => setObservacao(e.target.value)}
                    maxLength={500}
                    placeholder={alvo === "nao_compareceu" ? "Ex.: não entrou na sala em 15 minutos" : "Ex.: entrevista concluída sem intercorrências"}
                  />
                </div>
                <div className="field">
                  <label htmlFor={`pres-link-${inscricaoId}`}>Link da gravação da reunião</label>
                  <input
                    id={`pres-link-${inscricaoId}`}
                    type="url"
                    value={link}
                    onChange={(e) => setLink(e.target.value)}
                    placeholder="https://"
                    maxLength={500}
                  />
                  <p className="hint">Opcional. Gravação em áudio e vídeo, quando tecnicamente viável (item 6.5.6).</p>
                </div>
                {erro ? (
                  <p className="err" role="alert">
                    {erro}
                  </p>
                ) : null}
                <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", flexWrap: "wrap" }}>
                  <button type="button" className="btn" disabled={salvando} onClick={() => ref.current?.close()}>
                    Cancelar
                  </button>
                  <button type="button" className={`btn ${alvo === "nao_compareceu" ? "btn-perigo" : "btn-sucesso"}`} disabled={salvando} onClick={continuar}>
                    {salvando ? <span className="spin" aria-hidden /> : null} Salvar
                  </button>
                </div>
              </>
            )}
          </div>
        </div>
      </dialog>
    </div>
  );
}
