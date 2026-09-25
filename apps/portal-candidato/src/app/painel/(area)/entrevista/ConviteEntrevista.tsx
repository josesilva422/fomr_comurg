"use client";

import { useRef, useState } from "react";
import { TITULO_PADRAO, montarConviteEntrevista } from "@/lib/convite-entrevista";
import type { Grupo, Nivel } from "@/lib/tipos";

interface Props {
  inscricaoId: string;
  nome: string;
  grupo: Grupo;
  nivel: Nivel;
  jaConvidado?: boolean;
  aoEnviar?: () => void;
  pequeno?: boolean;
}

interface Resposta {
  ok?: boolean;
  enviado?: boolean;
  email?: string;
  assunto?: string;
  texto?: string;
  erro?: string;
}

const hojeSP = () => new Date().toLocaleDateString("en-CA", { timeZone: "America/Sao_Paulo" });

// Botão "Convidar para a entrevista" + pop-up com título, data, horário, link da reunião e orientações adicionais.
// Envia o e-mail padrão (src/lib/convite-entrevista.ts) ao candidato convocado (item 6.5.1).
export function ConviteEntrevista({ inscricaoId, nome, grupo, nivel, jaConvidado, aoEnviar, pequeno }: Props) {
  const ref = useRef<HTMLDialogElement>(null);
  const [titulo, setTitulo] = useState(TITULO_PADRAO);
  const [data, setData] = useState("");
  const [horario, setHorario] = useState("");
  const [link, setLink] = useState("");
  const [orientacoes, setOrientacoes] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState("");
  const [resultado, setResultado] = useState<Resposta | null>(null);

  const completo = titulo.trim().length >= 3 && data && horario && /^https:\/\/\S+$/i.test(link.trim());
  const previa = completo
    ? montarConviteEntrevista({ nome, grupo, nivel, titulo: titulo.trim(), data, horario, link: link.trim(), orientacoes })
    : null;

  function abrir(e: React.MouseEvent) {
    e.stopPropagation();
    setErro("");
    setResultado(null);
    ref.current?.showModal();
  }

  async function enviar() {
    setErro("");
    if (!completo) return setErro("Preencha título, data, horário e o link da reunião (começando com https://).");
    if (data < hojeSP()) return setErro("A data da entrevista já passou.");
    setEnviando(true);
    const r = await fetch("/api/painel/convite-entrevista", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ inscricao_id: inscricaoId, titulo: titulo.trim(), data, horario, link: link.trim(), orientacoes: orientacoes.trim() }),
    })
      .then((x) => x.json() as Promise<Resposta>)
      .catch(() => ({ erro: "Falha de conexão. Tente de novo." }) as Resposta);
    setEnviando(false);
    if (r.erro) return setErro(r.erro);
    setResultado(r);
    aoEnviar?.();
  }

  return (
    <>
      <button type="button" className={`btn${pequeno ? " btn-sm" : ""}${jaConvidado ? "" : " btn-primary"}`} onClick={abrir}>
        {jaConvidado ? "Reenviar convite" : "Convidar para entrevista"}
      </button>

      <dialog
        ref={ref}
        className="modal-motor"
        aria-labelledby={`convite-titulo-${inscricaoId}`}
        onClick={(e) => {
          e.stopPropagation();
          if (e.target === ref.current) ref.current?.close();
        }}
        onKeyDown={(e) => e.stopPropagation()}
      >
        <div className="modal-motor-caixa" style={{ width: "min(640px, 100%)" }}>
          <header className="modal-motor-topo">
            <div>
              <h2 id={`convite-titulo-${inscricaoId}`}>Convite para a entrevista técnica</h2>
              <p className="hint" style={{ margin: 0 }}>
                {nome} · o candidato recebe um e-mail padrão e vê o convite na área do candidato.
              </p>
            </div>
            <button type="button" className="btn btn-sm btn-ghost" onClick={() => ref.current?.close()} aria-label="Fechar">
              ✕
            </button>
          </header>

          <div className="modal-motor-corpo">
            {resultado ? (
              <div style={{ display: "grid", gap: 12 }}>
                {resultado.enviado ? (
                  <div className="alert alert-ok" style={{ margin: 0 }}>
                    <p>
                      Convite enviado por e-mail para <b>{resultado.email}</b>. Ele também aparece na área do candidato.
                    </p>
                  </div>
                ) : (
                  <>
                    <div className="alert alert-warn" style={{ margin: 0 }}>
                      <p>
                        O convite foi registrado e já aparece na área do candidato, mas o <b>e-mail não foi enviado</b> (envio de e-mail não configurado
                        no servidor ou falha). Copie o texto abaixo e envie para <b>{resultado.email}</b>.
                      </p>
                    </div>
                    <div className="field">
                      <label htmlFor={`convite-texto-${inscricaoId}`}>Assunto: {resultado.assunto}</label>
                      <textarea id={`convite-texto-${inscricaoId}`} rows={14} readOnly value={resultado.texto} onFocus={(e) => e.currentTarget.select()} />
                    </div>
                    <p>
                      <button type="button" className="btn btn-sm" onClick={() => void navigator.clipboard?.writeText(`${resultado.assunto}\n\n${resultado.texto}`)}>
                        Copiar texto
                      </button>
                    </p>
                  </>
                )}
                <p>
                  <button type="button" className="btn btn-primary" onClick={() => ref.current?.close()}>
                    Fechar
                  </button>
                </p>
              </div>
            ) : (
              <div style={{ display: "grid", gap: 4 }}>
                <div className="field">
                  <label htmlFor={`cv-titulo-${inscricaoId}`}>Título</label>
                  <input id={`cv-titulo-${inscricaoId}`} value={titulo} maxLength={150} onChange={(e) => setTitulo(e.target.value)} />
                </div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
                  <div className="field">
                    <label htmlFor={`cv-data-${inscricaoId}`}>Data</label>
                    <input id={`cv-data-${inscricaoId}`} type="date" min={hojeSP()} value={data} onChange={(e) => setData(e.target.value)} />
                  </div>
                  <div className="field">
                    <label htmlFor={`cv-hora-${inscricaoId}`}>Horário (Brasília)</label>
                    <input id={`cv-hora-${inscricaoId}`} type="time" value={horario} onChange={(e) => setHorario(e.target.value)} />
                  </div>
                </div>
                <div className="field">
                  <label htmlFor={`cv-link-${inscricaoId}`}>Link da reunião</label>
                  <input
                    id={`cv-link-${inscricaoId}`}
                    type="url"
                    inputMode="url"
                    placeholder="https://meet.google.com/... ou https://teams.microsoft.com/..."
                    value={link}
                    maxLength={500}
                    onChange={(e) => setLink(e.target.value)}
                  />
                </div>
                <div className="field">
                  <label htmlFor={`cv-orient-${inscricaoId}`}>Orientações adicionais (opcional)</label>
                  <textarea
                    id={`cv-orient-${inscricaoId}`}
                    rows={3}
                    maxLength={2000}
                    placeholder="Ex.: entrar na sala 10 minutos antes; ter em mãos documento oficial com foto."
                    value={orientacoes}
                    onChange={(e) => setOrientacoes(e.target.value)}
                  />
                </div>

                {previa ? (
                  <details>
                    <summary>Ver a mensagem que será enviada</summary>
                    <p className="hint" style={{ margin: "8px 0 4px" }}>
                      Assunto: <b>{previa.assunto}</b>
                    </p>
                    <pre style={{ whiteSpace: "pre-wrap", fontFamily: "inherit", fontSize: 14, margin: 0 }}>{previa.texto}</pre>
                    <p className="hint">Se o candidato se autodeclarou negro(a), o e-mail inclui o aviso da heteroidentificação na data da entrevista.</p>
                  </details>
                ) : null}

                {erro ? (
                  <p className="err" role="alert">
                    {erro}
                  </p>
                ) : null}
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 8 }}>
                  <button type="button" className="btn btn-primary" disabled={enviando} onClick={() => void enviar()}>
                    {enviando ? "Enviando…" : "Enviar convite"}
                  </button>
                  <button type="button" className="btn btn-ghost" onClick={() => ref.current?.close()}>
                    Cancelar
                  </button>
                </div>
                {jaConvidado ? (
                  <p className="hint" style={{ margin: 0 }}>
                    Este candidato já recebeu convite. Um novo convite substitui o anterior na área do candidato; o histórico fica registrado.
                  </p>
                ) : null}
              </div>
            )}
          </div>
        </div>
      </dialog>
    </>
  );
}
