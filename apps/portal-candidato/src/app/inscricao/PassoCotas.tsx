"use client";

import { useState } from "react";
import { CampoArquivo } from "@/components/CampoArquivo";
import { Pendencias } from "@/components/Pendencias";
import { createClient } from "@/lib/supabase/client";
import { traduzirErro } from "@/lib/validacao";
import { docsDoTipo, type Contexto } from "./contexto";

// Laudo: emitido em até 12 meses antes do encerramento das inscrições (item 10.5).
const LAUDO_MIN = "2025-10-07";
const LAUDO_MAX = "2026-10-07";

export function PassoCotas({ ctx }: { ctx: Contexto }) {
  const insc = ctx.inscricao!;
  const [pcd, setPcd] = useState(insc.cota_pcd);
  const [dataLaudo, setDataLaudo] = useState(insc.data_laudo ?? "");
  const [racial, setRacial] = useState(insc.cota_racial);
  const [isencao, setIsencao] = useState(insc.solicitou_isencao);
  const [justificativa, setJustificativa] = useState(insc.justificativa_isencao ?? "");
  const [erros, setErros] = useState<Record<string, string>>({});
  const [erroGeral, setErroGeral] = useState("");
  const [tentou, setTentou] = useState(false);
  const faltam = tentou ? ctx.pendencias.filter((p) => p.etapa === 5) : [];
  const [salvando, setSalvando] = useState(false);

  async function salvar() {
    setErroGeral("");
    setTentou(false);
    const e: Record<string, string> = {};
    if (pcd) {
      if (!dataLaudo) e.dataLaudo = "Informe a data de emissão do laudo.";
      else if (dataLaudo < LAUDO_MIN || dataLaudo > LAUDO_MAX)
        e.dataLaudo = "O laudo deve ter sido emitido a partir de 07/10/2025 (até 12 meses antes do encerramento).";
    }
    if (isencao && justificativa.trim().length < 10) e.justificativa = "Explique o motivo do pedido de isenção.";
    setErros(e);
    if (Object.keys(e).length) return;
    setSalvando(true);
    const { error } = await createClient()
      .from("inscricoes")
      .update({
        cota_pcd: pcd,
        data_laudo: pcd ? dataLaudo : null,
        cota_racial: racial,
        solicitou_isencao: isencao,
        justificativa_isencao: isencao ? justificativa.trim() : null,
      })
      .eq("id", insc.id);
    if (error) {
      setSalvando(false);
      return setErroGeral(traduzirErro(error));
    }
    const pend = await ctx.recarregar();
    setSalvando(false);
    setTentou(true);
    if (!pend.some((p) => p.etapa === 5)) ctx.irPara(6);
  }

  return (
    <section className="card step">
      <header className="step-head">
        <p className="eyebrow">Etapa 5 de 7</p>
        <h2>Cotas e isenção da taxa</h2>
        <p className="lead">Esta etapa é opcional. Marque apenas o que se aplica ao seu caso.</p>
      </header>

      <div className="alert alert-info">
        <p>
          Laudo médico e autodeclaração são <b>dados sensíveis</b> (LGPD). O acesso é restrito a perfis autorizados da
          Comissão e todo acesso fica registrado.
        </p>
      </div>

      <div className="toggles">
        <label className="toggle">
          <input type="checkbox" checked={pcd} onChange={(e) => setPcd(e.target.checked)} />
          <span className="track" />
          <span>
            <strong>Desejo concorrer às vagas reservadas para pessoas com deficiência</strong>
            <small>Se for o seu caso, você poderá anexar o laudo médico. A reserva é de 5% das vagas, com preferência no cadastro de reserva.</small>
          </span>
        </label>
        {pcd ? (
          <div className="reveal">
            <div className={`field${erros.dataLaudo ? " invalid" : ""}`}>
              <label htmlFor="dataLaudo">
                Data de emissão do laudo{" "}
                <b className="req" aria-hidden="true">
                  *
                </b>
              </label>
              <input id="dataLaudo" type="date" value={dataLaudo} onChange={(e) => setDataLaudo(e.target.value)} />
              <p className="hint">
                O laudo deve ter sido emitido em até 12 meses antes do encerramento das inscrições, ou seja, a partir de
                07/10/2025 (item 10.5).
              </p>
              {erros.dataLaudo ? (
                <p className="err" role="alert">
                  {erros.dataLaudo}
                </p>
              ) : null}
            </div>
            <CampoArquivo
              inscricaoId={insc.id}
              tipo="laudo_pcd"
              rotulo="Laudo médico"
              dica="Com CID e descrição da deficiência, assinado pelo médico."
              obrigatorio
              multiplo
              docs={docsDoTipo(ctx.documentos, "laudo_pcd")}
              aoMudar={ctx.recarregar}
            />
          </div>
        ) : null}

        <label className="toggle">
          <input type="checkbox" checked={racial} onChange={(e) => setRacial(e.target.checked)} />
          <span className="track" />
          <span>
            <strong>Desejo concorrer como candidato(a) negro(a) (preto ou pardo)</strong>
            <small>Reserva de 20% das vagas, com preferência no cadastro de reserva. Sujeito à heteroidentificação.</small>
          </span>
        </label>
        {racial ? (
          <div className="reveal">
            <CampoArquivo
              inscricaoId={insc.id}
              tipo="autodeclaracao_racial"
              rotulo="Autodeclaração racial assinada"
              dica="Use o modelo publicado junto ao edital."
              obrigatorio
              docs={docsDoTipo(ctx.documentos, "autodeclaracao_racial")}
              aoMudar={ctx.recarregar}
            />
          </div>
        ) : null}

        <label className="toggle">
          <input type="checkbox" checked={isencao} onChange={(e) => setIsencao(e.target.checked)} />
          <span className="track" />
          <span>
            <strong>Solicito isenção da taxa de inscrição</strong>
            <small>Pedido fundamentado, com documentação, dentro do período de inscrições (itens 4.10 e 4.10.1).</small>
          </span>
        </label>
        {isencao ? (
          <div className="reveal">
            <div className={`field${erros.justificativa ? " invalid" : ""}`}>
              <label htmlFor="justificativa">
                Fundamentação do pedido{" "}
                <b className="req" aria-hidden="true">
                  *
                </b>
              </label>
              <textarea id="justificativa" value={justificativa} onChange={(e) => setJustificativa(e.target.value)} placeholder="Explique o motivo do pedido de isenção." />
              {erros.justificativa ? (
                <p className="err" role="alert">
                  {erros.justificativa}
                </p>
              ) : null}
            </div>
            <CampoArquivo
              inscricaoId={insc.id}
              tipo="requerimento_isencao"
              rotulo="Requerimento de isenção e documentos que comprovam a situação"
              dica="Modelo publicado junto ao edital, assinado. Anexe também os documentos citados na fundamentação (pode enviar mais de um arquivo)."
              obrigatorio
              multiplo
              docs={docsDoTipo(ctx.documentos, "requerimento_isencao")}
              aoMudar={ctx.recarregar}
            />
            <div className="alert alert-warn" style={{ margin: 0 }}>
              <p>
                A resposta ao pedido sai até <b>09/10/2026</b>. Se for indeferido depois do encerramento das inscrições, <b>a
                inscrição é desconsiderada</b> (item 4.10.2). Se preferir não correr esse risco, pague a taxa normalmente.
              </p>
            </div>
          </div>
        ) : null}
      </div>

      <Pendencias itens={faltam} />
      {erroGeral ? (
        <div className="alert alert-err" role="alert">
          <p>{erroGeral}</p>
        </div>
      ) : null}
      <div className="acoes-form">
        <button type="button" className="btn btn-primary" disabled={salvando} onClick={() => void salvar()}>
          {salvando ? <span className="spin" aria-hidden /> : null} Salvar e continuar →
        </button>
      </div>
    </section>
  );
}
