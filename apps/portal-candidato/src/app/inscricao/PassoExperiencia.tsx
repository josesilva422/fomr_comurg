"use client";

import { useState } from "react";
import { Campo } from "@/components/Campo";
import { CampoArquivo } from "@/components/CampoArquivo";
import { Pendencias } from "@/components/Pendencias";
import { createClient } from "@/lib/supabase/client";
import { NIVEIS } from "@/lib/requisitos";
import { formatarMeses, idsSimultaneos, intervalo, mesParaData, uniaoMeses } from "@/lib/experiencia";
import type { Nivel } from "@/lib/tipos";
import type { TipoDocumento, TipoVinculo, Vinculo } from "@/lib/tipos-inscricao";
import { traduzirErro } from "@/lib/validacao";
import type { Contexto } from "./contexto";

const DOCS_POR_VINCULO: Record<TipoVinculo, TipoDocumento[]> = {
  privado: ["experiencia_ctps", "experiencia_declaracao", "experiencia_contrato"],
  publico: ["experiencia_publica", "experiencia_contrato"],
  autonomo: ["experiencia_autonomo", "experiencia_declaracao"],
};

const DICA_DOCS: Record<TipoVinculo, string> = {
  privado:
    "CTPS: páginas de identificação e de registro (se a função estiver em branco ou ilegível, anexe também a declaração do empregador). Declaração e contrato: papel timbrado, carimbo do CNPJ, assinatura e período exato.",
  publico:
    "Certidão ou declaração do órgão em papel timbrado, com assinatura e carimbo institucional, nome e CPF, cargo, período exato e atividades.",
  autonomo:
    "Contrato, RPA ou nota fiscal precisam vir acompanhados de declaração do contratante (papel timbrado, carimbo do CNPJ, assinatura, objeto, período e atividades).",
};

function opcoesDocumento(tipo: TipoVinculo | "", nivel: Nivel | null): TipoDocumento[] {
  if (!tipo) return [];
  const lista = [...DOCS_POR_VINCULO[tipo], "art_rrt_acervo" as TipoDocumento];
  if (nivel === "senior") lista.push("declaracao_lideranca");
  return lista;
}

const MES_MAXIMO = "2026-10";

function CartaoVinculo({
  ctx,
  vinculo,
  numero,
  simultaneo,
  aoFechar,
}: {
  ctx: Contexto;
  vinculo?: Vinculo;
  numero: number;
  simultaneo: boolean;
  aoFechar?: () => void;
}) {
  const [tipo, setTipo] = useState<TipoVinculo | "">(vinculo?.tipo ?? "");
  const [empregador, setEmpregador] = useState(vinculo?.empregador_contratante ?? "");
  const [cargo, setCargo] = useState(vinculo?.cargo ?? "");
  const [inicio, setInicio] = useState(vinculo?.inicio.slice(0, 7) ?? "");
  const [fim, setFim] = useState(vinculo?.fim?.slice(0, 7) ?? "");
  const [ativo, setAtivo] = useState(vinculo?.ativo ?? false);
  const [descricao, setDescricao] = useState(vinculo?.descricao ?? "");
  const [erros, setErros] = useState<Record<string, string>>({});
  const [erroGeral, setErroGeral] = useState("");
  const [ocupado, setOcupado] = useState(false);
  const [confirmando, setConfirmando] = useState(false);

  async function salvar() {
    setErroGeral("");
    const e: Record<string, string> = {};
    if (!tipo) e.tipo = "Selecione uma opção.";
    if (empregador.trim().length < 2) e.empregador = "Informe o empregador ou contratante.";
    if (cargo.trim().length < 2) e.cargo = "Informe o cargo ou função.";
    if (!/^\d{4}-\d{2}$/.test(inicio)) e.inicio = "Informe o mês de início (mês/ano).";
    if (!ativo) {
      if (!/^\d{4}-\d{2}$/.test(fim)) e.fim = "Informe o mês de fim ou marque “vínculo ativo”.";
      else if (/^\d{4}-\d{2}$/.test(inicio) && fim < inicio) e.fim = "O fim não pode ser anterior ao início.";
    }
    if (inicio > MES_MAXIMO || (!ativo && fim > MES_MAXIMO)) e.inicio = "Os períodos não podem passar de outubro/2026 (encerramento das inscrições).";
    if (descricao.trim().length < 10) e.descricao = "Descreva as atividades (mínimo de 10 caracteres).";
    setErros(e);
    if (Object.keys(e).length) return;
    setOcupado(true);
    const dados = {
      tipo,
      empregador_contratante: empregador.trim(),
      cargo: cargo.trim(),
      inicio: mesParaData(inicio),
      fim: ativo ? null : mesParaData(fim),
      ativo,
      descricao: descricao.trim(),
    };
    const supabase = createClient();
    const { error } = vinculo
      ? await supabase.from("vinculos_declarados").update(dados).eq("id", vinculo.id)
      : await supabase.from("vinculos_declarados").insert({ inscricao_id: ctx.inscricao!.id, ...dados });
    if (error) {
      setOcupado(false);
      return setErroGeral(traduzirErro(error));
    }
    await ctx.recarregar();
    setOcupado(false);
    aoFechar?.();
  }

  async function remover() {
    if (!vinculo) return aoFechar?.();
    setOcupado(true);
    const supabase = createClient();
    await supabase.from("documentos").update({ ativo: false }).eq("vinculo_id", vinculo.id).eq("ativo", true);
    const { error } = await supabase.from("vinculos_declarados").delete().eq("id", vinculo.id);
    if (error) setErroGeral(traduzirErro(error));
    await ctx.recarregar();
    setOcupado(false);
  }

  const opcoes = opcoesDocumento(vinculo?.tipo ?? tipo, ctx.inscricao?.nivel ?? null);

  return (
    <div className="item">
      <div className="item-head">
        <div>
          <strong className="item-title">Vínculo {numero}</strong>
          {simultaneo ? <span className="badge badge-warn">Simultâneo com outro vínculo</span> : null}
        </div>
        {confirmando ? (
          <span style={{ display: "flex", gap: 6, alignItems: "center", fontSize: 14 }}>
            Remover este vínculo?
            <button type="button" className="btn btn-quiet" disabled={ocupado} onClick={() => void remover()}>
              Sim, remover
            </button>
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setConfirmando(false)}>
              Cancelar
            </button>
          </span>
        ) : (
          <button type="button" className="btn btn-quiet" disabled={ocupado} onClick={() => (vinculo ? setConfirmando(true) : aoFechar?.())}>
            Remover
          </button>
        )}
      </div>

      <div className="grid">
        <Campo id={`v-tipo-${numero}`} rotulo="Tipo de vínculo" obrigatorio erro={erros.tipo}>
          <select id={`v-tipo-${numero}`} value={tipo} onChange={(e) => setTipo(e.target.value as TipoVinculo | "")}>
            <option value="">Selecione</option>
            <option value="privado">Setor privado (CLT ou contrato)</option>
            <option value="publico">Setor público</option>
            <option value="autonomo">Autônomo ou prestação de serviços</option>
          </select>
        </Campo>
        <Campo id={`v-emp-${numero}`} rotulo="Empregador ou contratante" obrigatorio erro={erros.empregador}>
          <input id={`v-emp-${numero}`} value={empregador} onChange={(e) => setEmpregador(e.target.value)} placeholder="Nome da empresa ou órgão" />
        </Campo>
        <Campo id={`v-cargo-${numero}`} rotulo="Cargo ou função" obrigatorio erro={erros.cargo}>
          <input id={`v-cargo-${numero}`} value={cargo} onChange={(e) => setCargo(e.target.value)} />
        </Campo>
        <div />
        <Campo id={`v-ini-${numero}`} rotulo="Início (mês/ano)" obrigatorio erro={erros.inicio}>
          <input id={`v-ini-${numero}`} type="month" value={inicio} max={MES_MAXIMO} placeholder="AAAA-MM" onChange={(e) => setInicio(e.target.value)} />
        </Campo>
        <Campo id={`v-fim-${numero}`} rotulo="Fim (mês/ano)" erro={erros.fim}>
          <input
            id={`v-fim-${numero}`}
            type="month"
            value={ativo ? "" : fim}
            max={MES_MAXIMO}
            placeholder="AAAA-MM"
            disabled={ativo}
            onChange={(e) => setFim(e.target.value)}
          />
          <label className="check">
            <input
              type="checkbox"
              checked={ativo}
              onChange={(e) => {
                setAtivo(e.target.checked);
                if (e.target.checked) setFim("");
              }}
            />
            Vínculo ativo (sem data de fim)
          </label>
        </Campo>
        <Campo
          id={`v-desc-${numero}`}
          rotulo="Descrição das atividades"
          obrigatorio
          erro={erros.descricao}
          dica="Declarações genéricas, que não ligam você à atividade, não são consideradas (item 5.5.1)."
          className="full"
        >
          <textarea id={`v-desc-${numero}`} value={descricao} onChange={(e) => setDescricao(e.target.value)} placeholder="Descreva o que você fazia neste vínculo, de forma objetiva." />
        </Campo>
      </div>

      {erroGeral ? (
        <div className="alert alert-err" role="alert">
          <p>{erroGeral}</p>
        </div>
      ) : null}

      <div className="docs">
        <h4>Documentos que comprovam este vínculo</h4>
        {vinculo ? (
          <>
            <p className="hint">{DICA_DOCS[vinculo.tipo]}</p>
            <CampoArquivo
              inscricaoId={ctx.inscricao!.id}
              tipo={opcoes[0]}
              opcoesTipo={opcoes}
              rotulo="Documento"
              obrigatorio
              multiplo
              referencia={{ vinculo_id: vinculo.id }}
              docs={ctx.documentos.filter((d) => d.vinculo_id === vinculo.id)}
              aoMudar={ctx.recarregar}
            />
          </>
        ) : (
          <p className="hint">Salve o vínculo para liberar o envio dos documentos.</p>
        )}
      </div>

      <div className="acoes-form" style={{ marginTop: 12 }}>
        <button type="button" className="btn btn-sm" disabled={ocupado} onClick={() => void salvar()}>
          {ocupado ? <span className="spin" aria-hidden /> : null} {vinculo ? "Salvar alterações" : "Salvar vínculo"}
        </button>
      </div>
    </div>
  );
}

export function PassoExperiencia({ ctx }: { ctx: Contexto }) {
  const nivel = ctx.inscricao?.nivel ?? null;
  const [novos, setNovos] = useState<number[]>([]);
  const [contador, setContador] = useState(1);
  const [tentou, setTentou] = useState(false);
  // pendências ao vivo: some da lista assim que o candidato resolve (o banco recalcula a cada mudança)
  const faltam = tentou ? ctx.pendencias.filter((p) => p.etapa === 4) : [];
  const [salvando, setSalvando] = useState(false);

  const simultaneos = idsSimultaneos(ctx.vinculos);
  const validos = ctx.vinculos.map(intervalo).filter((x): x is [number, number] => x !== null);
  const soma = validos.reduce((t, [s, e]) => t + (e - s + 1), 0);
  const contam = uniaoMeses(validos);
  const minimo = nivel ? NIVEIS[nivel].minAnos * 12 : null;

  async function continuar() {
    setTentou(false);
    setSalvando(true);
    const pend = await ctx.recarregar();
    setSalvando(false);
    setTentou(true);
    if (!pend.some((p) => p.etapa === 4)) ctx.irPara(5);
  }

  return (
    <section className="card step">
      <header className="step-head">
        <p className="eyebrow">Etapa 4 de 7</p>
        <h2>Experiência profissional</h2>
        <p className="lead">
          Cadastre cada vínculo com período e comprovação. O tempo é contado <b>em meses</b> e períodos simultâneos contam
          uma só vez.
        </p>
      </header>

      <div className="alert alert-warn">
        <div>
          <p>
            <b>Declare todos os vínculos, inclusive os simultâneos</b> (item 5.4.3). Omitir vínculo concomitante para
            pontuar indevidamente é falsidade e leva à eliminação (item 14.3).
          </p>
          <p>Estágios curriculares, bolsas, monitorias e trabalho voluntário não contam como experiência.</p>
        </div>
      </div>
      {nivel === "senior" ? (
        <div className="alert alert-info">
          <p>
            <b>Nível Sênior:</b> a liderança técnica ou responsabilidade principal exige <b>declaração específica</b> do
            contratante, com descrição explícita das responsabilidades (item 5.3.4). Anexe-a como “Declaração específica de
            liderança técnica”.
          </p>
        </div>
      ) : null}

      <div className="repeater">
        {ctx.vinculos.map((v, i) => (
          <CartaoVinculo key={v.id} ctx={ctx} vinculo={v} numero={i + 1} simultaneo={simultaneos.has(v.id)} />
        ))}
        {novos.map((k, i) => (
          <CartaoVinculo
            key={`novo-${k}`}
            ctx={ctx}
            numero={ctx.vinculos.length + i + 1}
            simultaneo={false}
            aoFechar={() => setNovos((l) => l.filter((x) => x !== k))}
          />
        ))}
        {ctx.vinculos.length === 0 && novos.length === 0 ? <div className="empty">Nenhum vínculo cadastrado ainda.</div> : null}
      </div>
      <button
        type="button"
        className="btn add"
        onClick={() => {
          setNovos((l) => [...l, contador]);
          setContador((c) => c + 1);
        }}
      >
        + Adicionar vínculo
      </button>

      {ctx.vinculos.length > 0 ? (
        <div className="exp-summary" aria-live="polite">
          <h4>Contagem estimada do seu tempo</h4>
          <div className="exp-nums">
            <div>
              Soma simples dos vínculos<b>{formatarMeses(soma)}</b>
            </div>
            <div>
              Tempo que conta (sem sobreposição)<b className="big">{formatarMeses(contam)}</b>
            </div>
          </div>
          <p style={{ marginTop: 10, fontSize: 14 }}>
            {minimo == null ? (
              <span className="hint">Escolha o grupo e o nível na etapa 2 para comparar com o mínimo exigido.</span>
            ) : contam >= minimo ? (
              <span style={{ color: "var(--ok-text)" }}>
                Em quantidade, o tempo declarado atinge o mínimo de {formatarMeses(minimo)} do nível. A Comissão confere se
                as atividades são da área exigida.
              </span>
            ) : (
              <span style={{ color: "var(--warn-text)" }}>
                O tempo declarado ainda está abaixo do mínimo de {formatarMeses(minimo)} para este nível.
              </span>
            )}
          </p>
          <p className="hint">
            Estimativa informativa. O tempo é contado em meses, com início e fim incluídos; vínculo ativo é contado até
            07/10/2026. A contagem oficial é feita pela Comissão (itens 5.4.1 e 5.4.2).
          </p>
        </div>
      ) : null}

      <Pendencias itens={faltam} />
      <div className="acoes-form">
        <button type="button" className="btn btn-primary" disabled={salvando} onClick={() => void continuar()}>
          {salvando ? <span className="spin" aria-hidden /> : null} Continuar →
        </button>
      </div>
    </section>
  );
}
