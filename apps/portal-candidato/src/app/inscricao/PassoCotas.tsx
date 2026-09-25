"use client";

import { useState } from "react";
import { CampoArquivo } from "@/components/CampoArquivo";
import { Pendencias } from "@/components/Pendencias";
import { createClient } from "@/lib/supabase/client";
import { traduzirErro } from "@/lib/validacao";
import { docsDoTipo, type Contexto } from "./contexto";

// Laudo: emitido em até 12 meses antes do encerramento das inscrições (item 10.5).
const LAUDO_MIN = "2025-10-13";
const LAUDO_MAX = "2026-10-13";

type Hipotese = "cadunico" | "doador_sangue" | "doador_medula";

// Hipóteses e documentos exigidos: decreto municipal citado no edital (item 4.10.1), arts. 1º, 3º e 4º.
const HIPOTESES: Record<Hipotese, { rotulo: string; requisito: string; documentoRotulo: string; documentoDica: string }> = {
  cadunico: {
    rotulo: "Membro de família de baixa renda inscrito no CadÚnico",
    requisito:
      "renda familiar mensal de até 3 salários mínimos, ou renda per capita de até meio salário mínimo, e inscrição no CadÚnico. A Comissão confere as informações junto ao órgão gestor do programa.",
    documentoRotulo: "Declaração formal de que você atende à condição de família de baixa renda",
    documentoDica: "Anexe a declaração formal (junto com o NIS informado acima). Pode enviar mais de um arquivo.",
  },
  doador_sangue: {
    rotulo: "Doador de sangue",
    requisito:
      "no mínimo 3 doações de sangue nos 363 dias anteriores à abertura das inscrições (28/09/2026). Doação de plaquetas ou de outro componente do sangue não vale.",
    documentoRotulo: "Comprovantes das doações de sangue",
    documentoDica:
      "Comprovantes emitidos por órgão oficial ou entidade credenciada pela União, Estado ou Município, com número e data de cada doação. Envie todos (pode enviar mais de um arquivo).",
  },
  doador_medula: {
    rotulo: "Doador de medula óssea",
    requisito: "no mínimo 1 doação de medula óssea nos 365 dias anteriores à abertura das inscrições (28/09/2026).",
    documentoRotulo: "Comprovante da doação de medula óssea e inscrição no REDOME",
    documentoDica:
      "Comprovante expedido pela unidade coletora, assinado pela autoridade competente, com qualificação civil, data e horário da coleta, e a cópia da inscrição no REDOME. Pode enviar mais de um arquivo.",
  },
};

export function PassoCotas({ ctx }: { ctx: Contexto }) {
  const insc = ctx.inscricao!;
  const [pcd, setPcd] = useState(insc.cota_pcd);
  const [dataLaudo, setDataLaudo] = useState(insc.data_laudo ?? "");
  const [racial, setRacial] = useState(insc.cota_racial);
  const [isencao, setIsencao] = useState(insc.solicitou_isencao);
  const [hipotese, setHipotese] = useState<Hipotese | "">(insc.hipotese_isencao ?? "");
  const [nis, setNis] = useState(insc.nis_isencao ?? "");
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
        e.dataLaudo = "O laudo deve ter sido emitido a partir de 13/10/2025 (até 12 meses antes do encerramento).";
    }
    if (isencao && !hipotese) e.hipotese = "Escolha a hipótese de isenção.";
    if (isencao && hipotese === "cadunico" && !nis.trim()) e.nis = "Informe o NIS (Número de Identificação Social do CadÚnico).";
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
        hipotese_isencao: isencao && hipotese ? hipotese : null,
        nis_isencao: isencao && hipotese === "cadunico" ? nis.trim() : null,
        justificativa_isencao: null,
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
            <small>Se for o seu caso, você poderá anexar o laudo médico. Você concorre ao mesmo tempo pela ampla concorrência e pela lista específica de pessoas com deficiência, respeitada a ordem de classificação.</small>
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
                13/10/2025.
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
            <small>Reserva de 20% das vagas, aplicada ao longo das convocações por alternância e proporcionalidade, respeitada a ordem de classificação. Sujeito à heteroidentificação, na data da entrevista.</small>
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
            <small>Pedido feito aqui no portal, no ato da inscrição, de 28/09 a 06/10/2026, nas hipóteses do decreto municipal (itens 4.10 e 4.10.1 do edital).</small>
          </span>
        </label>
        {isencao ? (
          <div className="reveal">
            <div className={`field${erros.hipotese ? " invalid" : ""}`}>
              <label htmlFor="hipotese">
                Hipótese de isenção{" "}
                <b className="req" aria-hidden="true">
                  *
                </b>
              </label>
              <select id="hipotese" value={hipotese} onChange={(e) => setHipotese(e.target.value as Hipotese | "")}>
                <option value="">Selecione</option>
                {(Object.keys(HIPOTESES) as Hipotese[]).map((h) => (
                  <option key={h} value={h}>
                    {HIPOTESES[h].rotulo}
                  </option>
                ))}
              </select>
              {erros.hipotese ? (
                <p className="err" role="alert">
                  {erros.hipotese}
                </p>
              ) : null}
            </div>
            {hipotese === "cadunico" ? (
              <div className={`field${erros.nis ? " invalid" : ""}`}>
                <label htmlFor="nis">
                  NIS (Número de Identificação Social do CadÚnico){" "}
                  <b className="req" aria-hidden="true">
                    *
                  </b>
                </label>
                <input id="nis" value={nis} onChange={(e) => setNis(e.target.value)} inputMode="numeric" placeholder="Número do NIS" />
                {erros.nis ? (
                  <p className="err" role="alert">
                    {erros.nis}
                  </p>
                ) : null}
              </div>
            ) : null}
            {hipotese ? (
              <>
                <div className="alert alert-ok" style={{ margin: 0 }}>
                  <p>
                    <b>Requisito:</b> {HIPOTESES[hipotese].requisito}
                  </p>
                </div>
                <CampoArquivo
                  inscricaoId={insc.id}
                  tipo="requerimento_isencao"
                  rotulo={HIPOTESES[hipotese].documentoRotulo}
                  dica={HIPOTESES[hipotese].documentoDica}
                  obrigatorio
                  multiplo
                  docs={docsDoTipo(ctx.documentos, "requerimento_isencao")}
                  aoMudar={ctx.recarregar}
                />
              </>
            ) : null}
            <div className="alert alert-warn" style={{ margin: 0 }}>
              <p>
                Pedido com dados incompletos ou incorretos é <b>indeferido</b> (decreto, art. 4º, §5º). Os documentos anexados não são devolvidos. A decisão
                sai até <b>08/10/2026</b>. Se o pedido for indeferido, você poderá pagar a taxa até <b>16/10/2026, às 23h59</b> (item 4.10.2 do edital); sem
                o pagamento nesse prazo, a inscrição é indeferida.
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
