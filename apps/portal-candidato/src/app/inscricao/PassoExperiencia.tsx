"use client";

import { useEffect, useRef, useState } from "react";
import { Campo } from "@/components/Campo";
import { CampoArquivo } from "@/components/CampoArquivo";
import { Pendencias } from "@/components/Pendencias";
import { createClient } from "@/lib/supabase/client";
import { NIVEIS } from "@/lib/requisitos";
import { faltaComprovante, formatarMeses, idsSimultaneos, intervalo, mesParaData, uniaoMeses } from "@/lib/experiencia";
import type { Nivel } from "@/lib/tipos";
import type { TipoDocumento, TipoVinculo, Vinculo } from "@/lib/tipos-inscricao";
import { traduzirErro } from "@/lib/validacao";
import type { Contexto, RascunhoVinculo } from "./contexto";

const DOCS_POR_VINCULO: Record<TipoVinculo, TipoDocumento[]> = {
  privado: ["experiencia_ctps", "experiencia_declaracao", "experiencia_contrato"],
  publico: ["experiencia_publica", "experiencia_contrato"],
  autonomo: ["experiencia_autonomo", "experiencia_declaracao"],
};

// Documentos aceitos, conforme o edital (itens 5.3.1 a 5.3.5 e Anexo III).
const DOCS_ACEITOS: Record<TipoVinculo, { regra: string; itens: string[] }> = {
  privado: {
    regra: "Anexe pelo menos um destes documentos (pode combinar mais de um):",
    itens: [
      "CTPS: páginas de identificação e de registro do contrato, com nome do empregador, cargo ou função, data de admissão e data de demissão (ou vínculo ativo). Se a função estiver em branco ou ilegível, anexe também a declaração do empregador.",
      "Declaração do empregador: em papel timbrado da empresa, com carimbo do CNPJ, assinatura do representante legal, seu nome completo e CPF, cargo ou função, período exato (início e fim, ou vínculo ativo) e descrição das atividades. Sem papel timbrado, carimbo ou assinatura, não é aceita.",
      "Contrato de trabalho ou de prestação de serviços: em papel timbrado, com carimbo do CNPJ, assinatura das partes, objeto ou escopo do contrato e período de vigência.",
    ],
  },
  publico: {
    regra: "Anexe pelo menos um destes documentos:",
    itens: [
      "Certidão ou declaração do órgão ou entidade: em papel timbrado, com assinatura do responsável e carimbo institucional, seu nome completo e CPF, cargo ou função, período exato e descrição das atividades.",
      "Contrato administrativo ou instrumento equivalente, com os mesmos elementos.",
    ],
  },
  autonomo: {
    regra: "Anexe os dois documentos:",
    itens: [
      "Contrato de prestação de serviços, RPA ou nota fiscal.",
      "Declaração do contratante: em papel timbrado, com carimbo do CNPJ, assinatura do responsável, objeto, período e atividades realizadas.",
    ],
  },
};

const DOCS_COMPLEMENTARES =
  "ART, RRT ou certidão de acervo técnico (quando houver) complementam, mas não substituem os documentos acima: devem ter relação com a experiência declarada e identificar profissional, contratante, objeto e período.";

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
  valoresIniciais,
  numero,
  simultaneo,
  aoFechar,
}: {
  ctx: Contexto;
  vinculo?: Vinculo;
  /** Só usado quando `vinculo` não é passado (cartão novo): pré-preenche a partir da leitura do currículo. */
  valoresIniciais?: RascunhoVinculo;
  numero: number;
  simultaneo: boolean;
  aoFechar?: () => void;
}) {
  const [tipo, setTipo] = useState<TipoVinculo | "">(vinculo?.tipo ?? valoresIniciais?.tipo ?? "");
  const [empregador, setEmpregador] = useState(vinculo?.empregador_contratante ?? valoresIniciais?.empregador_contratante ?? "");
  const [cargo, setCargo] = useState(vinculo?.cargo ?? valoresIniciais?.cargo ?? "");
  const [inicio, setInicio] = useState(vinculo?.inicio.slice(0, 7) ?? valoresIniciais?.inicio ?? "");
  const [fim, setFim] = useState(vinculo?.fim?.slice(0, 7) ?? valoresIniciais?.fim ?? "");
  const [ativo, setAtivo] = useState(vinculo?.ativo ?? valoresIniciais?.ativo ?? false);
  const [descricao, setDescricao] = useState(vinculo?.descricao ?? valoresIniciais?.descricao ?? "");
  const [vindoDoCV] = useState(!vinculo && Boolean(valoresIniciais));
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
  const faltando = vinculo
    ? faltaComprovante(
        vinculo.tipo,
        ctx.documentos.filter((d) => d.vinculo_id === vinculo.id && d.ativo).map((d) => d.tipo),
      )
    : null;

  return (
    <div className="item">
      <div className="item-head">
        <div>
          <strong className="item-title">Vínculo {numero}</strong>
          {simultaneo ? <span className="badge badge-warn">Simultâneo com outro vínculo</span> : null}
          {vindoDoCV ? <span className="badge badge-warn">Do currículo — confira antes de salvar</span> : null}
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
          dica="Declarações genéricas, que não ligam você à atividade, não são consideradas."
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
            <p className="hint" style={{ marginBottom: 4 }}>
              <b>Obrigatório.</b> {DOCS_ACEITOS[vinculo.tipo].regra}
            </p>
            <ul className="hint" style={{ margin: "0 0 8px 18px" }}>
              {DOCS_ACEITOS[vinculo.tipo].itens.map((t) => (
                <li key={t}>{t}</li>
              ))}
            </ul>
            <p className="hint">{DOCS_COMPLEMENTARES}</p>
            {ctx.inscricao?.nivel === "senior" ? (
              <p className="hint">
                Nível Sênior: para os anos de liderança técnica ou responsabilidade principal, anexe também a declaração específica do contratante,
                com descrição explícita das responsabilidades de liderança ou coordenação técnica. Declaração genérica não é aceita para esse fim.
              </p>
            ) : null}
            {faltando ? (
              <div className="alert alert-warn" style={{ margin: "8px 0" }}>
                <p>{faltando} Sem o comprovante, não é possível enviar a inscrição, e este vínculo não conta no tempo de experiência.</p>
              </div>
            ) : (
              <div className="alert alert-ok" style={{ margin: "8px 0" }}>
                <p>Comprovante anexado. A Comissão confere se o documento atende ao edital.</p>
              </div>
            )}
            <CampoArquivo
              inscricaoId={ctx.inscricao!.id}
              tipo={opcoes[0]}
              opcoesTipo={opcoes}
              rotulo="Documento"
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
  const [novos, setNovos] = useState<{ chave: number; valores?: RascunhoVinculo }[]>([]);
  const [contador, setContador] = useState(1);
  const [tentou, setTentou] = useState(false);
  // Guarda a REFERÊNCIA do último array já consumido: evita duplicar em desenvolvimento, onde o React
  // roda o efeito duas vezes de propósito (Strict Mode), e também se o efeito rodar de novo por outro motivo.
  const consumidoRef = useRef<RascunhoVinculo[] | null>(null);

  // Se a leitura do currículo (etapa 3) trouxe vínculos, cria um cartão pré-preenchido para cada um —
  // consumido uma única vez (senão duplicaria ao voltar/avançar de etapa, ou em Strict Mode).
  useEffect(() => {
    if (ctx.rascunhosVinculosCV.length === 0) return;
    if (consumidoRef.current === ctx.rascunhosVinculosCV) return;
    consumidoRef.current = ctx.rascunhosVinculosCV;
    const trazidos = ctx.rascunhosVinculosCV;
    const criados = trazidos.map((valores, i) => ({ chave: contador + i, valores }));
    setNovos((atual) => [...atual, ...criados]);
    setContador(contador + trazidos.length);
    ctx.definirRascunhosVinculosCV([]);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ctx.rascunhosVinculosCV]);
  // pendências ao vivo: some da lista assim que o candidato resolve (o banco recalcula a cada mudança)
  const faltam = tentou ? ctx.pendencias.filter((p) => p.etapa === 4) : [];
  const [salvando, setSalvando] = useState(false);

  const simultaneos = idsSimultaneos(ctx.vinculos);
  const validos = ctx.vinculos.map(intervalo).filter((x): x is [number, number] => x !== null);
  const soma = validos.reduce((t, [s, e]) => t + (e - s + 1), 0);
  // Só vínculo com comprovante conta no tempo (edital 3.1 "comprovar" e 5.3; mesma regra do banco).
  const comprovados = ctx.vinculos.filter(
    (v) => faltaComprovante(v.tipo, ctx.documentos.filter((d) => d.vinculo_id === v.id && d.ativo).map((d) => d.tipo)) === null,
  );
  const semComprovante = ctx.vinculos.length - comprovados.length;
  const contam = uniaoMeses(comprovados.map(intervalo).filter((x): x is [number, number] => x !== null));
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
            <b>Declare todos os vínculos, inclusive os simultâneos.</b> Omitir vínculo concomitante para
            pontuar indevidamente é falsidade e leva à eliminação.
          </p>
          <p>Estágios curriculares, bolsas, monitorias e trabalho voluntário não contam como experiência.</p>
        </div>
      </div>
      {nivel === "senior" ? (
        <div className="alert alert-info">
          <p>
            <b>Nível Sênior:</b> a liderança técnica ou responsabilidade principal exige <b>declaração específica</b> do
            contratante, com descrição explícita das responsabilidades. Anexe-a como “Declaração específica de
            liderança técnica”.
          </p>
        </div>
      ) : null}

      <div className="repeater">
        {ctx.vinculos.map((v, i) => (
          <CartaoVinculo key={v.id} ctx={ctx} vinculo={v} numero={i + 1} simultaneo={simultaneos.has(v.id)} />
        ))}
        {novos.map((n, i) => (
          <CartaoVinculo
            key={`novo-${n.chave}`}
            ctx={ctx}
            numero={ctx.vinculos.length + i + 1}
            simultaneo={false}
            valoresIniciais={n.valores}
            aoFechar={() => setNovos((l) => l.filter((x) => x.chave !== n.chave))}
          />
        ))}
        {ctx.vinculos.length === 0 && novos.length === 0 ? <div className="empty">Nenhum vínculo cadastrado ainda.</div> : null}
      </div>
      <button
        type="button"
        className="btn add"
        onClick={() => {
          setNovos((l) => [...l, { chave: contador }]);
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
              Tempo que conta (comprovado, sem sobreposição)<b className="big">{formatarMeses(contam)}</b>
            </div>
          </div>
          {semComprovante > 0 ? (
            <p className="hint" style={{ marginTop: 8, color: "var(--warn-text)" }}>
              {semComprovante === 1 ? "1 vínculo ainda está" : `${semComprovante} vínculos ainda estão`} sem comprovante e não entra
              {semComprovante === 1 ? "" : "m"} nesta contagem.
            </p>
          ) : null}
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
            13/10/2026. A contagem oficial é feita pela Comissão (itens 5.4.1 e 5.4.2).
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
