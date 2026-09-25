"use client";

import { useCallback, useEffect, useState } from "react";
import { CampoArquivo } from "@/components/CampoArquivo";
import { createClient } from "@/lib/supabase/client";
import type { Documento } from "@/lib/tipos-inscricao";

export interface MinhaIsencao {
  decisao: "deferida" | "indeferida" | "desconsiderada" | "pagamento_confirmado" | "pagamento_recusado";
  motivo: string;
  decidido_em: string;
  pode_pagar: boolean;
  prazo_pagamento: string;
}

interface DadosPagamento {
  pix_chave: string;
  tipo_chave: string;
  favorecido: string;
  valor_centavos: number;
}

const brl = (c: number) => (c / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
const fmt = (v: string) => new Date(v).toLocaleString("pt-BR", { dateStyle: "long", timeStyle: "short", timeZone: "America/Sao_Paulo" });

const fmtCurto = (v: string) =>
  new Date(v).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" });

/** Decisão sobre o PRÓPRIO pedido de isenção, dados do Pix e comprovantes anexados (null enquanto carrega). */
export function useMinhaIsencao(ativo: boolean) {
  const [res, setRes] = useState<MinhaIsencao | null>(null);
  const [dados, setDados] = useState<DadosPagamento | null>(null);
  const [docs, setDocs] = useState<Documento[]>([]);

  const buscar = useCallback(async () => {
    const supabase = createClient();
    const [{ data: i }, { data: d }, { data: c }] = await Promise.all([
      supabase.rpc("minha_isencao"),
      supabase.rpc("dados_pagamento"),
      supabase.from("documentos").select("*").eq("ativo", true).eq("tipo", "comprovante_pix").order("enviado_em"),
    ]);
    return {
      isencao: (i as MinhaIsencao[] | null)?.[0] ?? null,
      pagamento: (d as DadosPagamento[] | null)?.[0] ?? null,
      comprovantes: (c as Documento[] | null) ?? [],
    };
  }, []);

  const aplicar = useCallback((r: Awaited<ReturnType<typeof buscar>>) => {
    setRes(r.isencao);
    setDados(r.pagamento);
    setDocs(r.comprovantes);
  }, []);

  const carregar = useCallback(async () => aplicar(await buscar()), [aplicar, buscar]);

  useEffect(() => {
    if (!ativo) return;
    let vivo = true;
    void buscar().then((r) => {
      if (vivo) aplicar(r);
    });
    return () => {
      vivo = false;
    };
  }, [ativo, buscar, aplicar]);

  return { res, dados, docs, carregar };
}

/** Há comprovante enviado DEPOIS da última decisão (ex.: novo comprovante após uma recusa)? */
function comprovanteNovo(res: MinhaIsencao, docs: Documento[]): boolean {
  return docs.some((d) => new Date(d.enviado_em).getTime() > new Date(res.decidido_em).getTime());
}

/** Texto da "Situação" da inscrição enquanto ela está no fluxo da isenção. */
export function situacaoIsencao(res: MinhaIsencao | null, docs: Documento[]): string {
  if (!res) return "aguardando análise do pedido de isenção";
  if (res.decisao === "deferida") return "isenção deferida — aguardando homologação";
  if (res.decisao === "desconsiderada") return "inscrição desconsiderada (taxa não paga no prazo)";
  if (res.decisao === "pagamento_confirmado") return "pagamento confirmado — aguardando homologação";
  if (res.decisao === "pagamento_recusado") {
    if (comprovanteNovo(res, docs)) return "novo comprovante do Pix enviado, aguardando conferência da Comissão";
    return res.pode_pagar
      ? `comprovante do Pix recusado — envie um novo até ${fmtCurto(res.prazo_pagamento)}`
      : "comprovante do Pix recusado — prazo de pagamento encerrado";
  }
  if (docs.length > 0) return "isenção indeferida — comprovante do Pix enviado, aguardando conferência da Comissão";
  if (res.pode_pagar) return `isenção indeferida — pagamento da taxa pendente (até ${fmtCurto(res.prazo_pagamento)})`;
  return "isenção indeferida — prazo de pagamento encerrado";
}

// Resultado do pedido de isenção, visto só pelo próprio candidato. Se indeferida e dentro do prazo (item 4.10.2),
// mostra como pagar e permite anexar o comprovante do Pix.
export function ResultadoIsencao({ inscricaoId, isencao }: { inscricaoId: string; isencao: ReturnType<typeof useMinhaIsencao> }) {
  const { res, dados, docs, carregar } = isencao;
  const [copiado, setCopiado] = useState(false);

  if (!res) return null;

  async function copiar() {
    if (!dados) return;
    try {
      await navigator.clipboard.writeText(dados.pix_chave);
      setCopiado(true);
      setTimeout(() => setCopiado(false), 2000);
    } catch {
      /* sem permissão de área de transferência: o candidato copia manualmente */
    }
  }

  if (res.decisao === "deferida") {
    return (
      <section className="card" style={{ marginTop: 16 }}>
        <h3>Isenção deferida</h3>
        <p>Seu pedido de isenção foi deferido em {fmt(res.decidido_em)}. Não há taxa a pagar.</p>
        <p className="hint">Motivo registrado pela Comissão: {res.motivo}</p>
      </section>
    );
  }

  if (res.decisao === "desconsiderada") {
    return (
      <section className="card" style={{ marginTop: 16 }}>
        <h3>Inscrição desconsiderada</h3>
        <p>
          Seu pedido de isenção foi indeferido e a taxa não foi paga no prazo (item 4.10.2 do edital). Por isso a inscrição foi desconsiderada, em{" "}
          {fmt(res.decidido_em)}.
        </p>
        <p className="hint">Motivo registrado pela Comissão: {res.motivo}</p>
      </section>
    );
  }

  if (res.decisao === "pagamento_confirmado") {
    return (
      <section className="card" style={{ marginTop: 16 }}>
        <h3>Pagamento confirmado</h3>
        <p>A Comissão conferiu o seu comprovante do Pix em {fmt(res.decidido_em)}. A inscrição segue normalmente.</p>
      </section>
    );
  }

  const recusado = res.decisao === "pagamento_recusado";
  // Depois de uma recusa, só conta como enviado o comprovante mandado DEPOIS dela.
  const enviados = recusado ? docs.filter((d) => new Date(d.enviado_em).getTime() > new Date(res.decidido_em).getTime()) : docs;

  return (
    <section className="card" style={{ marginTop: 16 }}>
      <h3>{recusado ? "Comprovante do Pix recusado" : "Isenção indeferida"}</h3>
      {recusado ? (
        <div className="alert alert-err">
          <p>
            A Comissão recusou o comprovante do Pix em {fmt(res.decidido_em)}. <b>Motivo:</b> {res.motivo}
          </p>
          <p>Remova o comprovante anterior (×) e envie um comprovante válido dentro do prazo.</p>
        </div>
      ) : (
        <>
          <p>Seu pedido de isenção foi indeferido em {fmt(res.decidido_em)}.</p>
          <p className="hint">Motivo registrado pela Comissão: {res.motivo}</p>
        </>
      )}

      {res.pode_pagar ? (
        <>
          <div className="alert alert-warn">
            <p>
              Para manter a inscrição, pague a taxa por Pix e anexe o comprovante <b>até {fmt(res.prazo_pagamento)}</b> (item 4.10.2 do edital). Sem o pagamento
              nesse prazo, a inscrição é desconsiderada. Esta é a única alteração permitida na sua inscrição.
            </p>
          </div>
          <div className="pix">
            <div>
              <small>Chave Pix ({dados?.tipo_chave === "email" ? "e-mail" : dados?.tipo_chave ?? "…"})</small>
              <div className="pix-key">{dados ? dados.pix_chave : "Carregando…"}</div>
              <small style={{ marginTop: 6 }}>Favorecido: {dados?.favorecido ?? "COMURG"}</small>
              <button type="button" className="btn btn-sm" style={{ marginTop: 12 }} onClick={() => void copiar()} disabled={!dados}>
                {copiado ? "Copiado!" : "Copiar chave"}
              </button>
            </div>
            <div>
              <small>Valor</small>
              <div className="valor">{dados ? brl(dados.valor_centavos) : "R$ 100,00"}</div>
              <small style={{ marginTop: 6 }}>O Pix precisa ser feito por você, de conta em seu nome.</small>
            </div>
          </div>
          <CampoArquivo
            inscricaoId={inscricaoId}
            tipo="comprovante_pix"
            rotulo="Comprovante de pagamento"
            dica="PDF, JPG ou PNG legível, com seu nome, CPF (pode ser parcial), data e horário, valor e código E2E. Escolha o arquivo e clique em “Enviar comprovante”."
            obrigatorio
            docs={docs}
            aoMudar={carregar}
            botaoEnviar="Enviar comprovante"
          />
          {enviados.length > 0 ? (
            <div className="alert alert-ok" style={{ marginTop: 12 }}>
              <p>
                <b>✓ Comprovante enviado em {fmt(enviados[enviados.length - 1].enviado_em)}.</b> Não é preciso fazer mais nada: a Comissão vai conferir o
                pagamento. Se anexou o arquivo errado, remova-o (×) e envie o correto até o prazo.
              </p>
            </div>
          ) : null}
        </>
      ) : enviados.length > 0 ? (
        <div className="alert alert-ok">
          <p>
            <b>✓ Comprovante enviado em {fmt(enviados[enviados.length - 1].enviado_em)}.</b> A Comissão vai conferir o pagamento.
          </p>
        </div>
      ) : (
        <p className="hint">O prazo para pagamento terminou. A Comissão decidirá sobre a inscrição.</p>
      )}
    </section>
  );
}
