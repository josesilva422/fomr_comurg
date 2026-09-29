"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { textoData, type ItemCronograma } from "@/lib/portal";

// Cronograma (Anexo IV) mostrado na página inicial. Alteração só com justificativa (ex.: retificação), auditada.
export function CronogramaEditor() {
  const [itens, setItens] = useState<ItemCronograma[] | null>(null);
  const [erro, setErro] = useState("");
  const [editando, setEditando] = useState<number | null>(null);
  const [versao, setVersao] = useState(0);

  useEffect(() => {
    createClient()
      .schema("painel")
      .rpc("listar_cronograma")
      .then(({ data, error }: { data: ItemCronograma[] | null; error: { message: string } | null }) => {
        if (error) setErro(error.message);
        else setItens(data ?? []);
      });
  }, [versao]);

  if (erro) return <p className="err">{erro}</p>;
  if (!itens) return <p className="hint">Carregando…</p>;

  return (
    <ol className="crono">
      {itens.map((c) =>
        editando === c.ordem ? (
          <li key={c.ordem} style={{ padding: "12px 4px", borderBottom: "1px solid var(--line)" }}>
            <EditarItem
              item={c}
              aoFechar={() => setEditando(null)}
              aoSalvar={() => {
                setEditando(null);
                setVersao((v) => v + 1);
              }}
            />
          </li>
        ) : (
          <li key={c.ordem} className="crono-item">
            <span className="crono-marca" aria-hidden>
              {c.ordem}
            </span>
            <span className="crono-evento">{c.evento}</span>
            <span className="crono-data" style={{ display: "flex", gap: 8, alignItems: "center", justifyContent: "flex-end" }}>
              {textoData(c)}
              <button type="button" className="btn btn-sm btn-ghost" onClick={() => setEditando(c.ordem)}>
                Editar
              </button>
            </span>
          </li>
        ),
      )}
    </ol>
  );
}

function EditarItem({ item, aoFechar, aoSalvar }: { item: ItemCronograma; aoFechar: () => void; aoSalvar: () => void }) {
  const [evento, setEvento] = useState(item.evento);
  const [inicio, setInicio] = useState(item.data_inicio ?? "");
  const [fim, setFim] = useState(item.data_fim ?? "");
  const [detalhe, setDetalhe] = useState(item.detalhe ?? "");
  const [justificativa, setJustificativa] = useState("");
  const [erro, setErro] = useState("");
  const [salvando, setSalvando] = useState(false);

  async function salvar() {
    setErro("");
    if (justificativa.trim().length < 5) return setErro("Informe a justificativa (ex.: Retificação nº 1, publicada em …).");
    setSalvando(true);
    const { error } = await createClient().schema("painel").rpc("salvar_cronograma_item", {
      p_ordem: item.ordem,
      p_evento: evento.trim(),
      p_data_inicio: inicio || null,
      p_data_fim: fim || null,
      p_detalhe: detalhe.trim() || null,
      p_justificativa: justificativa.trim(),
    });
    setSalvando(false);
    if (error) return setErro(error.message);
    aoSalvar();
  }

  return (
    <div style={{ display: "grid", gap: 4 }}>
      <b>Item {item.ordem}</b>
      <div className="field">
        <label htmlFor={`ev-${item.ordem}`}>Evento</label>
        <input id={`ev-${item.ordem}`} value={evento} onChange={(e) => setEvento(e.target.value)} />
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
        <div className="field">
          <label htmlFor={`ini-${item.ordem}`}>Data inicial (vazia = &quot;Até …&quot;)</label>
          <input id={`ini-${item.ordem}`} type="date" value={inicio} onChange={(e) => setInicio(e.target.value)} />
        </div>
        <div className="field">
          <label htmlFor={`fim-${item.ordem}`}>Data final</label>
          <input id={`fim-${item.ordem}`} type="date" value={fim} onChange={(e) => setFim(e.target.value)} />
        </div>
      </div>
      <div className="field">
        <label htmlFor={`det-${item.ordem}`}>Texto da data (opcional, substitui as datas na página; ex.: &quot;19, 20 e 21/10/2026&quot;)</label>
        <input id={`det-${item.ordem}`} value={detalhe} onChange={(e) => setDetalhe(e.target.value)} />
      </div>
      <div className="field">
        <label htmlFor={`jus-${item.ordem}`}>Justificativa (obrigatória, fica na auditoria)</label>
        <input id={`jus-${item.ordem}`} value={justificativa} onChange={(e) => setJustificativa(e.target.value)} placeholder="Retificação nº 1" />
      </div>
      {erro ? <p className="err">{erro}</p> : null}
      <div style={{ display: "flex", gap: 8 }}>
        <button type="button" className="btn btn-sm btn-primary" disabled={salvando} onClick={() => void salvar()}>
          {salvando ? "Salvando…" : "Salvar"}
        </button>
        <button type="button" className="btn btn-sm btn-ghost" onClick={aoFechar}>
          Cancelar
        </button>
      </div>
    </div>
  );
}
