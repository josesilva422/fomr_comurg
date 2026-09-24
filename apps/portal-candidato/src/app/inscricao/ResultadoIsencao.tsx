"use client";

import { useCallback, useEffect, useState } from "react";
import { CampoArquivo } from "@/components/CampoArquivo";
import { createClient } from "@/lib/supabase/client";
import type { Documento } from "@/lib/tipos-inscricao";

interface MinhaIsencao {
  decisao: "deferida" | "indeferida" | "desconsiderada";
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

// Resultado do pedido de isenção, visto só pelo próprio candidato. Se indeferida e dentro do prazo (item 4.10.2),
// mostra como pagar e permite anexar o comprovante do Pix.
export function ResultadoIsencao({ inscricaoId }: { inscricaoId: string }) {
  const [res, setRes] = useState<MinhaIsencao | null>(null);
  const [dados, setDados] = useState<DadosPagamento | null>(null);
  const [docs, setDocs] = useState<Documento[]>([]);
  const [copiado, setCopiado] = useState(false);

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
    let vivo = true;
    void buscar().then((r) => {
      if (vivo) aplicar(r);
    });
    return () => {
      vivo = false;
    };
  }, [buscar, aplicar]);

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

  return (
    <section className="card" style={{ marginTop: 16 }}>
      <h3>Isenção indeferida</h3>
      <p>Seu pedido de isenção foi indeferido em {fmt(res.decidido_em)}.</p>
      <p className="hint">Motivo registrado pela Comissão: {res.motivo}</p>

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
            dica="PDF, JPG ou PNG legível, com seu nome, CPF (pode ser parcial), data e horário, valor e código E2E."
            obrigatorio
            docs={docs}
            aoMudar={carregar}
          />
        </>
      ) : (
        <p className="hint">O prazo para pagamento terminou. A Comissão decidirá sobre a inscrição.</p>
      )}
    </section>
  );
}
