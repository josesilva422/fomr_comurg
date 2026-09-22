"use client";

import { useEffect, useState } from "react";
import { CampoArquivo } from "@/components/CampoArquivo";
import { Pendencias } from "@/components/Pendencias";
import { createClient } from "@/lib/supabase/client";
import { docsDoTipo, type Contexto } from "./contexto";

interface DadosPagamento {
  pix_chave: string;
  tipo_chave: string;
  favorecido: string;
  valor_centavos: number;
}

const brl = (centavos: number) => (centavos / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

export function PassoPagamento({ ctx }: { ctx: Contexto }) {
  const insc = ctx.inscricao!;
  const [dados, setDados] = useState<DadosPagamento | null>(null);
  const [copiado, setCopiado] = useState(false);
  const [tentou, setTentou] = useState(false);
  const faltam = tentou ? ctx.pendencias.filter((p) => p.etapa === 6) : [];

  useEffect(() => {
    let vivo = true;
    createClient()
      .rpc("dados_pagamento")
      .then(({ data }: { data: DadosPagamento[] | null }) => {
        if (vivo && data?.[0]) setDados(data[0]);
      });
    return () => {
      vivo = false;
    };
  }, []);

  async function copiar() {
    if (!dados) return;
    try {
      await navigator.clipboard.writeText(dados.pix_chave);
    } catch {
      /* clipboard indisponível: o candidato copia manualmente */
    }
    setCopiado(true);
    setTimeout(() => setCopiado(false), 2500);
  }

  async function continuar() {
    setTentou(false);
    const pend = await ctx.recarregar();
    setTentou(true);
    if (!pend.some((p) => p.etapa === 6)) ctx.irPara(7);
  }

  return (
    <section className="card step">
      <header className="step-head">
        <p className="eyebrow">Etapa 6 de 7</p>
        <h2>Pagamento da taxa (Pix)</h2>
        <p className="lead">
          A taxa de inscrição é de <b>{dados ? brl(dados.valor_centavos) : "R$ 100,00"}</b>, paga por Pix para a chave da
          COMURG. Depois de pagar, anexe o comprovante.
        </p>
      </header>

      {insc.solicitou_isencao ? (
        <div className="alert alert-ok">
          <p>
            Você pediu isenção. Enquanto o pedido estiver em análise, o comprovante é <b>opcional</b>. Sua inscrição ficará
            com o status <b>aguardando isenção</b>.
          </p>
        </div>
      ) : null}

      <div className="pix">
        <div>
          <small>Chave Pix ({dados?.tipo_chave === "email" ? "e-mail" : dados?.tipo_chave ?? "…"})</small>
          <div className="pix-key" style={{ fontSize: 22, wordBreak: "break-all" }}>
            {dados ? dados.pix_chave : "Carregando…"}
          </div>
          <small style={{ marginTop: 6 }}>Favorecido: {dados?.favorecido ?? "COMURG"} — Companhia de Urbanização de Goiânia</small>
          <button type="button" className="btn btn-sm" style={{ marginTop: 12 }} onClick={() => void copiar()} disabled={!dados}>
            {copiado ? "Copiado!" : "Copiar chave"}
          </button>
        </div>
        <div>
          <small>Valor</small>
          <div className="valor">{dados ? brl(dados.valor_centavos) : "R$ 100,00"}</div>
          <small style={{ marginTop: 6 }}>Sem restituição, exceto cancelamento total do certame (item 4.11).</small>
        </div>
      </div>

      <div className="alert alert-warn">
        <div>
          <p>
            <b>O Pix precisa ser feito por você.</b> Use uma conta de sua titularidade. Pagamento feito por terceiros não é
            aceito (item 4.9.1).
          </p>
          <p>
            Só valem comprovantes com data e hora entre <b>24/09/2026 e 07/10/2026</b> (item 4.9.5).
          </p>
        </div>
      </div>

      <h3 style={{ marginTop: 22 }}>Como pagar</h3>
      <ol className="steps-list">
        <li>No aplicativo do seu banco, escolha Pix › Pagar com chave.</li>
        <li>
          Cole a chave e confira o favorecido e o valor de {dados ? brl(dados.valor_centavos) : "R$ 100,00"}.
        </li>
        <li>Pague de uma conta em seu nome e guarde o comprovante (PDF ou imagem).</li>
      </ol>

      <h3>O comprovante precisa mostrar</h3>
      <ul className="checklist">
        <li>Seu nome completo e CPF (pode aparecer parcialmente, como o banco mostra)</li>
        <li>Data e horário do pagamento</li>
        <li>Valor de {dados ? brl(dados.valor_centavos) : "R$ 100,00"}</li>
        <li>Código da transação (E2E ID)</li>
      </ul>

      <div className="grid" style={{ marginTop: 20 }}>
        <div className="full">
          <CampoArquivo
            inscricaoId={insc.id}
            tipo="comprovante_pix"
            rotulo="Comprovante de pagamento"
            dica="PDF, JPG ou PNG legível. Sem o comprovante, a inscrição não é concluída (item 4.9.3), a não ser que você tenha pedido isenção."
            obrigatorio={!insc.solicitou_isencao}
            docs={docsDoTipo(ctx.documentos, "comprovante_pix")}
            aoMudar={ctx.recarregar}
          />
        </div>
      </div>

      <Pendencias itens={faltam} />
      <div className="acoes-form">
        <button type="button" className="btn btn-primary" onClick={() => void continuar()}>
          Salvar e continuar →
        </button>
      </div>
    </section>
  );
}
