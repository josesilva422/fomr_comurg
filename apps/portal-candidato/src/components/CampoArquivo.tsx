"use client";

import { useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { enviarArquivo, removerDocumento, tamanhoLegivel, type ReferenciaDocumento } from "@/lib/armazenamento";
import { exigeSomentePdf, ROTULO_DOCUMENTO, type Documento, type TipoDocumento } from "@/lib/tipos-inscricao";

interface Props {
  inscricaoId: string;
  /** Tipo do documento (ou, com `opcoesTipo`, o tipo inicial). */
  tipo: TipoDocumento;
  /** Permite o candidato escolher o tipo do documento antes de enviar (ex.: comprovação de vínculo). */
  opcoesTipo?: TipoDocumento[];
  rotulo: string;
  dica?: string;
  obrigatorio?: boolean;
  multiplo?: boolean;
  referencia?: ReferenciaDocumento;
  /** Documentos já enviados deste campo (a tela pai filtra). */
  docs: Documento[];
  /** Chamado depois de enviar/remover, para a tela recarregar os dados. */
  aoMudar: () => Promise<unknown>;
}

export function CampoArquivo({ inscricaoId, tipo, opcoesTipo, rotulo, dica, obrigatorio, multiplo, referencia, docs, aoMudar }: Props) {
  const entrada = useRef<HTMLInputElement>(null);
  const [tipoEscolhido, setTipoEscolhido] = useState<TipoDocumento | "">(opcoesTipo ? "" : tipo);
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState("");

  async function aoEscolher(lista: FileList | null) {
    if (!lista || lista.length === 0) return;
    const escolhidos = multiplo ? [...lista] : [lista[0]];
    if (entrada.current) entrada.current.value = "";
    if (!tipoEscolhido) return setErro("Escolha primeiro o tipo do documento.");
    setErro("");
    setEnviando(true);
    const supabase = createClient();
    for (const arquivo of escolhidos) {
      const msg = await enviarArquivo(supabase, inscricaoId, tipoEscolhido, arquivo, referencia);
      if (msg) {
        setErro(msg);
        break;
      }
    }
    await aoMudar();
    setEnviando(false);
  }

  async function remover(id: string) {
    setErro("");
    setEnviando(true);
    const msg = await removerDocumento(createClient(), id);
    if (msg) setErro(msg);
    await aoMudar();
    setEnviando(false);
  }

  const mostrarBotao = multiplo || docs.length === 0;
  const somentePdf = exigeSomentePdf(tipoEscolhido || tipo);

  return (
    <div className={`upload${erro ? " invalid" : ""}`}>
      <div className="upload-top">
        <span className="upload-label">
          {rotulo}{" "}
          {obrigatorio ? (
            <b className="req" aria-hidden="true">
              *
            </b>
          ) : (
            <span className="opt">(opcional)</span>
          )}
        </span>
        {dica ? <span className="hint">{dica}</span> : null}
      </div>

      {opcoesTipo ? (
        <div className="field" style={{ marginBottom: 10 }}>
          <label>Tipo do documento</label>
          <select value={tipoEscolhido} onChange={(e) => setTipoEscolhido(e.target.value as TipoDocumento | "")}>
            <option value="">Selecione</option>
            {opcoesTipo.map((t) => (
              <option key={t} value={t}>
                {ROTULO_DOCUMENTO[t]}
              </option>
            ))}
          </select>
        </div>
      ) : null}

      {mostrarBotao ? (
        <button type="button" className="dropzone" disabled={enviando} onClick={() => entrada.current?.click()}>
          <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M12 16V4m0 0L7 9m5-5 5 5" />
            <path d="M4 16v3a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-3" />
          </svg>
          <span>
            {enviando ? (
              <b>Enviando…</b>
            ) : (
              <>
                <b>Selecionar arquivo</b> {multiplo ? "(pode enviar mais de um)" : ""}
              </>
            )}
            <small>{somentePdf ? "PDF · até 10 MB" : "PDF, JPG ou PNG · até 10 MB"}</small>
          </span>
        </button>
      ) : null}
      <input
        ref={entrada}
        type="file"
        className="sr-only"
        tabIndex={-1}
        accept={somentePdf ? ".pdf" : ".pdf,.jpg,.jpeg,.png"}
        multiple={multiplo}
        onChange={(e) => void aoEscolher(e.target.files)}
      />

      {docs.length > 0 ? (
        <ul className="files">
          {docs.map((d) => (
            <li key={d.id}>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" />
                <path d="M14 3v5h5" />
              </svg>
              <span className="file-name">
                {opcoesTipo ? `${ROTULO_DOCUMENTO[d.tipo]} · ` : ""}
                {d.nome_original}
              </span>
              <span className="file-size">{tamanhoLegivel(d.tamanho_bytes)}</span>
              <button type="button" className="icon-btn" disabled={enviando} aria-label={`Remover ${d.nome_original}`} onClick={() => void remover(d.id)}>
                ×
              </button>
            </li>
          ))}
        </ul>
      ) : null}

      {erro ? (
        <p className="err" role="alert">
          {erro}
        </p>
      ) : null}
    </div>
  );
}
