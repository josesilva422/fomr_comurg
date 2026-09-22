"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { formatarMeses, intervalo, uniaoMeses } from "@/lib/experiencia";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import { traduzirErro } from "@/lib/validacao";
import { docsDoTipo, type Contexto } from "./contexto";

const fmtData = (iso: string | null) => (iso ? iso.split("-").reverse().join("/") : "—");

const DECLARACOES = [
  "Declaro atender aos requisitos gerais do edital: nacionalidade brasileira ou portuguesa com direitos políticos, quitação eleitoral e militar (quando aplicável), 18 anos completos até o encerramento das inscrições, ausência de impedimento legal e de acúmulo indevido de cargos.",
  "Declaro que informei todos os meus vínculos profissionais, inclusive os simultâneos, e estou ciente de que omitir vínculo para pontuar indevidamente é falsidade (itens 5.4.3 e 14.3).",
  "Declaro que os documentos enviados são autênticos. Estou ciente de que falsidade documental, em qualquer fase, leva à eliminação imediata e à comunicação às autoridades (item 5.5.4).",
  "Estou ciente de que não é permitido incluir título ou experiência depois do encerramento das inscrições (item 5.5.3) e de que a taxa não é restituível (item 4.11).",
  "Estou ciente de que meus dados pessoais e sensíveis serão tratados apenas para este processo seletivo, conforme a LGPD, e de que a decisão final sobre habilitação e pontuação é sempre de pessoas da Comissão Organizadora.",
];

function Linha({ t, d }: { t: string; d: React.ReactNode }) {
  return (
    <div className="kv">
      <dt>{t}</dt>
      <dd>{d}</dd>
    </div>
  );
}

function Secao({ titulo, onEditar, children }: { titulo: string; onEditar: () => void; children: React.ReactNode }) {
  return (
    <div className="review">
      <div className="review-head">
        <h4>{titulo}</h4>
        <button type="button" className="btn btn-sm" onClick={onEditar}>
          Editar
        </button>
      </div>
      <div className="review-body">
        <dl>{children}</dl>
      </div>
    </div>
  );
}

export function PassoRevisao({ ctx }: { ctx: Contexto }) {
  const { candidato: c, inscricao: i } = ctx;
  const [marcadas, setMarcadas] = useState<boolean[]>(() => DECLARACOES.map(() => false));
  const [erro, setErro] = useState("");
  const [enviando, setEnviando] = useState(false);

  if (!c || !i) return null;

  const nDocs = ctx.documentos.length;
  const intervalos = ctx.vinculos.map(intervalo).filter((x): x is [number, number] => x !== null);
  const tempoQueConta = formatarMeses(uniaoMeses(intervalos));

  async function enviar() {
    setErro("");
    if (marcadas.some((m) => !m)) return setErro("Marque todas as declarações para enviar.");
    setEnviando(true);
    const supabase = createClient();
    const versao = "edital-v2-2026-09-21";
    const aceite = await supabase.rpc("aceitar_declaracoes", { p_versao: versao });
    if (aceite.error) {
      setEnviando(false);
      return setErro(traduzirErro(aceite.error));
    }
    const envio = await supabase.rpc("submeter_inscricao");
    if (envio.error) {
      setEnviando(false);
      const msg = /pendência/i.test(envio.error.message ?? "")
        ? "Ainda há pendências em outras etapas. Revise a lista de etapas ao lado."
        : traduzirErro(envio.error);
      return setErro(msg);
    }
    // recarrega: a inscrição volta com status "submetida"/"aguardando_isencao" e a tela muda para "Enviada"
    await ctx.recarregar();
    setEnviando(false);
  }

  return (
    <section className="card step">
      <header className="step-head">
        <p className="eyebrow">Etapa 7 de 7</p>
        <h2>Revisão e envio</h2>
        <p className="lead">
          Confira tudo com atenção. Ao clicar em <b>Enviar solicitação</b>, a inscrição é <b>definitiva</b>: não poderá
          mais ser alterada e só a Comissão Organizadora terá acesso às informações enviadas.
        </p>
      </header>

      {ctx.pendencias.length ? (
        <div className="alert alert-err" role="alert">
          <div>
            <p>
              <b>Ainda há pendências antes de enviar:</b>
            </p>
            <ul className="pend">
              {ctx.pendencias.map((p, idx) => (
                <li key={`${p.codigo}-${idx}`}>
                  <span>{p.mensagem}</span>
                  <button type="button" className="btn btn-sm" onClick={() => ctx.irPara(p.etapa)}>
                    Corrigir
                  </button>
                </li>
              ))}
            </ul>
          </div>
        </div>
      ) : (
        <div className="alert alert-ok">
          <p>Tudo certo. Falta apenas confirmar as declarações abaixo.</p>
        </div>
      )}

      <Secao titulo="Dados pessoais" onEditar={() => ctx.irPara(1)}>
        <Linha t="Nome" d={c.nome} />
        <Linha t="CPF" d={c.cpf.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4")} />
        <Linha t="Nascimento" d={fmtData(c.data_nascimento)} />
        <Linha t="Contato" d={`${c.email} · ${c.telefone}`} />
      </Secao>

      <Secao titulo="Vaga" onEditar={() => ctx.irPara(2)}>
        <Linha t="Grupo e nível" d={i.grupo && i.nivel ? `${GRUPOS[i.grupo].nome} · ${GRUPOS[i.grupo].descricao} · ${NIVEIS[i.nivel].nome}` : "—"} />
      </Secao>

      <Secao titulo="Formação" onEditar={() => ctx.irPara(3)}>
        <Linha t="Graduação" d={i.curso_graduacao ? `${i.curso_graduacao} (${i.grau_graduacao})` : "—"} />
        <Linha t="Instituição" d={i.instituicao_graduacao ? `${i.instituicao_graduacao}, colação em ${fmtData(i.data_colacao)}` : "—"} />
        <Linha t="Pós-graduação" d={`${ctx.titulos.length} título(s)`} />
        <Linha t="Cursos e certificações" d={`${ctx.cursos.length} item(ns)`} />
      </Secao>

      <Secao titulo="Experiência" onEditar={() => ctx.irPara(4)}>
        <Linha t="Vínculos declarados" d={String(ctx.vinculos.length)} />
        <Linha t="Tempo que conta (estimativa)" d={tempoQueConta} />
      </Secao>

      <Secao titulo="Cotas e isenção" onEditar={() => ctx.irPara(5)}>
        <Linha t="Vagas reservadas para pessoas com deficiência" d={i.cota_pcd ? "Sim" : "Não"} />
        <Linha t="Vagas reservadas para candidatos negros" d={i.cota_racial ? "Sim" : "Não"} />
        <Linha t="Pedido de isenção" d={i.solicitou_isencao ? "Sim" : "Não"} />
      </Secao>

      <Secao titulo="Pagamento" onEditar={() => ctx.irPara(6)}>
        <Linha t="Taxa" d={i.solicitou_isencao ? "Isenção solicitada (aguardando análise)" : "R$ 100,00 via Pix"} />
        <Linha t="Comprovante" d={docsDoTipo(ctx.documentos, "comprovante_pix").length ? "Anexado" : <span className="hint">não anexado</span>} />
        <Linha t="Documentos enviados no total" d={`${nDocs} arquivo(s)`} />
      </Secao>

      <h3 style={{ marginTop: 30 }}>Declarações</h3>
      <p className="sub">Leia e marque cada item para enviar.</p>
      {DECLARACOES.map((texto, idx) => (
        <div className="decl" key={idx}>
          <label className="check">
            <input
              type="checkbox"
              checked={marcadas[idx]}
              onChange={(e) =>
                setMarcadas((m) => {
                  const novo = [...m];
                  novo[idx] = e.target.checked;
                  return novo;
                })
              }
            />
            <span dangerouslySetInnerHTML={{ __html: idx === 4 ? `${texto} <em>(Texto provisório, a validar com o jurídico e o DPO.)</em>` : texto }} />
          </label>
        </div>
      ))}

      {erro ? (
        <div className="alert alert-err" role="alert">
          <p>{erro}</p>
        </div>
      ) : null}
      <div className="acoes-form">
        <button type="button" className="btn btn-primary" disabled={enviando} onClick={() => void enviar()}>
          {enviando ? <span className="spin" aria-hidden /> : null} Enviar solicitação
        </button>
      </div>
    </section>
  );
}
