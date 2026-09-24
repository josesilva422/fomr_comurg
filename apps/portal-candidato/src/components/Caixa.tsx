"use client";

import { useState, type ReactNode } from "react";

/** Sinal para abrir/recolher todas as caixas de uma área de uma vez (cada mudança gera um `v` novo). */
export interface SinalCaixas {
  v: number;
  aberto: boolean;
}

export function useSinalCaixas() {
  const [sinal, setSinal] = useState<SinalCaixas>({ v: 0, aberto: true });
  return {
    sinal,
    abrirTodas: () => setSinal((s) => ({ v: s.v + 1, aberto: true })),
    recolherTodas: () => setSinal((s) => ({ v: s.v + 1, aberto: false })),
  };
}

/** Caixa que pode ser minimizada (título sempre visível; o conteúdo recolhe). */
export function Caixa({
  titulo,
  selo,
  aberta = true,
  sinal,
  children,
}: {
  titulo: ReactNode;
  /** Etiqueta curta ao lado do título (pontos, situação…), visível mesmo com a caixa recolhida. */
  selo?: ReactNode;
  aberta?: boolean;
  sinal?: SinalCaixas;
  children: ReactNode;
}) {
  const [estaAberta, setEstaAberta] = useState(aberta);
  const [sinalVisto, setSinalVisto] = useState(sinal?.v ?? 0);
  // "Abrir/recolher todas": ajusta durante a renderização quando chega um sinal novo (padrão recomendado do React).
  if (sinal && sinal.v !== sinalVisto) {
    setSinalVisto(sinal.v);
    setEstaAberta(sinal.aberto);
  }
  return (
    <details className="caixa" open={estaAberta} onToggle={(e) => setEstaAberta((e.currentTarget as HTMLDetailsElement).open)}>
      <summary>
        <span className="caixa-titulo">{titulo}</span>
        {selo ? <span className="caixa-selo">{selo}</span> : null}
        <span className="caixa-seta" aria-hidden />
      </summary>
      <div className="caixa-corpo">{children}</div>
    </details>
  );
}

export function BarraCaixas({ abrirTodas, recolherTodas }: { abrirTodas: () => void; recolherTodas: () => void }) {
  return (
    <div className="barra-caixas">
      <button type="button" className="btn btn-sm btn-ghost" onClick={abrirTodas}>
        Expandir tudo
      </button>
      <button type="button" className="btn btn-sm btn-ghost" onClick={recolherTodas}>
        Recolher tudo
      </button>
    </div>
  );
}
