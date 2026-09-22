"use client";

import { useEffect, useRef, useState } from "react";
import { Pendencias } from "@/components/Pendencias";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS, REQUISITOS, VAGAS } from "@/lib/requisitos";
import type { Grupo, Nivel } from "@/lib/tipos";
import { traduzirErro } from "@/lib/validacao";
import type { Contexto } from "./contexto";

function Linha({ t, d }: { t: string; d: React.ReactNode }) {
  return (
    <div className="kv">
      <dt>{t}</dt>
      <dd>{d}</dd>
    </div>
  );
}

export function PassoVaga({ ctx }: { ctx: Contexto }) {
  const inscricao = ctx.inscricao!;
  const [grupo, setGrupo] = useState<Grupo | "">(inscricao.grupo ?? "");
  const [nivel, setNivel] = useState<Nivel | "">(inscricao.nivel ?? "");
  const [cursos, setCursos] = useState<string[] | null>(null);
  const [erros, setErros] = useState<Record<string, string>>({});
  const [erroGeral, setErroGeral] = useState("");
  const [tentou, setTentou] = useState(false);
  // pendências ao vivo: some da lista assim que o candidato resolve (o banco recalcula a cada mudança)
  const faltam = tentou ? ctx.pendencias.filter((p) => p.etapa === 2) : [];
  const [salvando, setSalvando] = useState(false);
  const pedido = useRef(0);

  async function buscarCursos(g: Grupo, n: Nivel) {
    const meu = ++pedido.current;
    const { data } = await createClient().from("cursos_aceitos").select("curso").eq("grupo", g).eq("nivel", n).order("curso");
    if (meu === pedido.current) setCursos((data ?? []).map((l: { curso: string }) => l.curso));
  }

  function escolher(g: Grupo | "", n: Nivel | "") {
    setGrupo(g);
    setNivel(n);
    setErros({});
    setCursos(null);
    if (g && n) void buscarCursos(g, n);
    else pedido.current++;
  }

  // carrega a lista de cursos quando a etapa abre com uma escolha já salva
  useEffect(() => {
    if (inscricao.grupo && inscricao.nivel) void buscarCursos(inscricao.grupo, inscricao.nivel);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function salvar(ev: React.FormEvent) {
    ev.preventDefault();
    setErroGeral("");
    setTentou(false);
    const e: Record<string, string> = {};
    if (!grupo) e.grupo = "Selecione uma opção.";
    if (!nivel) e.nivel = "Selecione uma opção.";
    setErros(e);
    if (Object.keys(e).length) return;
    setSalvando(true);
    const { error } = await createClient().from("inscricoes").update({ grupo, nivel }).eq("id", inscricao.id);
    if (error) {
      setSalvando(false);
      return setErroGeral(traduzirErro(error));
    }
    const pend = await ctx.recarregar();
    setSalvando(false);
    setTentou(true);
    if (!pend.some((p) => p.etapa === 2)) ctx.irPara(3);
  }

  const req = grupo && nivel ? REQUISITOS[grupo][nivel] : null;
  const engs = (cursos ?? []).filter((c) => c.startsWith("Engenharia"));
  const base = (cursos ?? []).filter((c) => !c.startsWith("Engenharia"));

  return (
    <form className="card step" onSubmit={salvar} noValidate>
      <header className="step-head">
        <p className="eyebrow">Etapa 2 de 7</p>
        <h2>Grupo e nível</h2>
        <p className="lead">
          Escolha o grupo e o nível da vaga. Cada candidato pode fazer <b>uma única inscrição</b>, em um grupo e um nível.
        </p>
      </header>

      <fieldset className={`group${erros.grupo ? " invalid" : ""}`}>
        <legend>
          Grupo{" "}
          <b className="req" aria-hidden="true">
            *
          </b>
        </legend>
        <div className="choices">
          {(Object.keys(GRUPOS) as Grupo[]).map((g) => (
            <label className="choice" key={g}>
              <input type="radio" name="grupo" value={g} checked={grupo === g} onChange={() => escolher(g, nivel)} />
              <span className="choice-body">
                <span className="choice-tag">{GRUPOS[g].nome}</span>
                <strong>{GRUPOS[g].descricao}</strong>
                <span className="choice-sub">{Object.values(VAGAS[g]).reduce((a, b) => a + b, 0)} vagas imediatas</span>
              </span>
            </label>
          ))}
        </div>
        {erros.grupo ? (
          <p className="err" role="alert">
            {erros.grupo}
          </p>
        ) : null}
      </fieldset>

      <fieldset className={`group${erros.nivel ? " invalid" : ""}`}>
        <legend>
          Nível{" "}
          <b className="req" aria-hidden="true">
            *
          </b>
        </legend>
        <div className="choices">
          {(Object.keys(NIVEIS) as Nivel[]).map((n) => (
            <label className="choice" key={n}>
              <input type="radio" name="nivel" value={n} checked={nivel === n} onChange={() => escolher(grupo, n)} />
              <span className="choice-body">
                <strong>{NIVEIS[n].nome}</strong>
                <span className="choice-sub">
                  Experiência mínima: {NIVEIS[n].minAnos} {NIVEIS[n].minAnos > 1 ? "anos" : "ano"}
                </span>
                {grupo ? (
                  <span className="choice-sub">
                    {VAGAS[grupo][n]} {VAGAS[grupo][n] > 1 ? "vagas" : "vaga"} no {GRUPOS[grupo].nome}
                  </span>
                ) : null}
              </span>
            </label>
          ))}
        </div>
        {erros.nivel ? (
          <p className="err" role="alert">
            {erros.nivel}
          </p>
        ) : null}
      </fieldset>

      {grupo && nivel && req ? (
        <div className="panel">
          <h3>
            O que é exigido: {GRUPOS[grupo].nome} · {NIVEIS[nivel].nome}
          </h3>
          <dl>
            <Linha t="Vagas imediatas" d={`${VAGAS[grupo][nivel]} ${VAGAS[grupo][nivel] > 1 ? "vagas" : "vaga"}`} />
            <Linha
              t="Graduação aceita"
              d={
                cursos === null ? (
                  <span className="hint">Carregando…</span>
                ) : (
                  <>
                    <div className="chips">
                      {base.map((c) => (
                        <span className="chip" key={c}>
                          {c}
                        </span>
                      ))}
                    </div>
                    {engs.length > 0 ? (
                      <details>
                        <summary>Ver as {engs.length} engenharias aceitas</summary>
                        <div className="chips" style={{ marginTop: 8 }}>
                          {engs.map((c) => (
                            <span className="chip" key={c}>
                              {c}
                            </span>
                          ))}
                        </div>
                      </details>
                    ) : null}
                    <p className="hint">Cursos tecnológicos (tecnólogo) não são aceitos em nenhum grupo ou nível.</p>
                  </>
                )
              }
            />
            <Linha
              t="Pós-graduação lato sensu"
              d={
                req.modo === "nao" ? (
                  <span className="tag tag-nao">Não exigida</span>
                ) : req.modo === "obrig" ? (
                  <>
                    <span className="tag tag-obrig">Obrigatória</span> {req.pos}
                  </>
                ) : (
                  <>
                    <span className="tag tag-equiv">Exigida ou equivalência</span> {req.pos}
                    <br />
                    <small style={{ color: "var(--muted)" }}>Equivalência: {req.equiv}</small>
                  </>
                )
              }
            />
            <Linha
              t="Experiência mínima"
              d={
                <b>
                  {NIVEIS[nivel].minAnos} {NIVEIS[nivel].minAnos > 1 ? "anos" : "ano"}
                </b>
              }
            />
            <Linha t="Atuação exigida" d={req.atuacao} />
          </dl>
        </div>
      ) : null}

      <div className="alert alert-info">
        <p>
          Os requisitos são avaliados na data de <b>encerramento das inscrições (07/10/2026)</b>. Não é exigido registro em
          conselho de classe.
        </p>
      </div>

      <Pendencias itens={faltam} />
      {erroGeral ? (
        <div className="alert alert-err" role="alert">
          <p>{erroGeral}</p>
        </div>
      ) : null}
      <div className="acoes-form">
        <button type="submit" className="btn btn-primary" disabled={salvando}>
          {salvando ? <span className="spin" aria-hidden /> : null} Salvar e continuar →
        </button>
      </div>
    </form>
  );
}
