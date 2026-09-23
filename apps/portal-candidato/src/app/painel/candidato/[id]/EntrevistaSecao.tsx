"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  BANCA_MINIMA, COMPETENCIAS, CORTE_ENTREVISTA, TOTAL_ENTREVISTA, faixa, fmtNota,
  type ChaveCompetencia, type EntrevistaDoCandidato, type FichaEntrevista,
} from "@/lib/entrevista";

type Campos = Record<ChaveCompetencia, string>;
const vazio = (): Campos => ({ dominio: "", analise: "", planejamento: "", comunicacao: "", caso: "", postura: "" });

// Entrevista técnica: a entrevista acontece fora do sistema; aqui a Comissão LANÇA a ficha de cada avaliador
// (nota por competência + justificativa, Anexo II). O sistema calcula ET (média), corte de 15 e PF = AC + ET.
export function EntrevistaSecao({ inscricaoId }: { inscricaoId: string }) {
  const [dados, setDados] = useState<EntrevistaDoCandidato | null>(null);
  const [erro, setErro] = useState("");
  const [avaliador, setAvaliador] = useState("");
  const [notas, setNotas] = useState<Campos>(vazio());
  const [justs, setJusts] = useState<Campos>(vazio());
  const [salvando, setSalvando] = useState(false);
  const [aviso, setAviso] = useState("");

  const [tick, setTick] = useState(0);
  const carregar = () => setTick((t) => t + 1);

  useEffect(() => {
    let vivo = true;
    createClient()
      .schema("painel")
      .rpc("entrevista_do_candidato", { p_inscricao_id: inscricaoId })
      .then(({ data, error }: { data: EntrevistaDoCandidato | null; error: { message: string } | null }) => {
        if (!vivo) return;
        if (error) setErro(error.message);
        else setDados(data);
      });
    return () => {
      vivo = false;
    };
  }, [inscricaoId, tick]);

  function limpar() {
    setAvaliador("");
    setNotas(vazio());
    setJusts(vazio());
  }

  function editar(f: FichaEntrevista) {
    setAviso("");
    setErro("");
    setAvaliador(f.avaliador_nome);
    setNotas({
      dominio: String(f.nota_dominio), analise: String(f.nota_analise), planejamento: String(f.nota_planejamento),
      comunicacao: String(f.nota_comunicacao), caso: String(f.nota_caso), postura: String(f.nota_postura),
    });
    setJusts({
      dominio: f.just_dominio, analise: f.just_analise, planejamento: f.just_planejamento,
      comunicacao: f.just_comunicacao, caso: f.just_caso, postura: f.just_postura,
    });
    document.getElementById("form-ficha")?.scrollIntoView({ behavior: "smooth" });
  }

  async function salvar() {
    setErro("");
    setAviso("");
    if (avaliador.trim().length < 3) return setErro("Informe o nome do avaliador.");
    for (const c of COMPETENCIAS) {
      const n = Number(notas[c.chave]);
      if (notas[c.chave] === "" || !Number.isInteger(n) || n < 0 || n > c.peso) return setErro(`"${c.rotulo}": use um número inteiro de 0 a ${c.peso}.`);
      if (justs[c.chave].trim().length < 3) return setErro(`Escreva a justificativa de "${c.rotulo}".`);
    }
    setSalvando(true);
    const { error } = await createClient().schema("painel").rpc("salvar_ficha_entrevista", {
      p_inscricao_id: inscricaoId,
      p_avaliador: avaliador.trim(),
      p_notas: Object.fromEntries(COMPETENCIAS.map((c) => [c.chave, Number(notas[c.chave])])),
      p_justificativas: Object.fromEntries(COMPETENCIAS.map((c) => [c.chave, justs[c.chave].trim()])),
    });
    setSalvando(false);
    if (error) return setErro(error.message);
    setAviso(`Ficha de ${avaliador.trim()} salva.`);
    limpar();
    carregar();
  }

  async function remover(f: FichaEntrevista) {
    const motivo = window.prompt(`Remover a ficha de ${f.avaliador_nome}? Informe o motivo (fica na auditoria):`);
    if (!motivo) return;
    const { error } = await createClient().schema("painel").rpc("remover_ficha_entrevista", { p_ficha_id: f.id, p_motivo: motivo });
    if (error) setErro(error.message);
    else carregar();
  }

  if (!dados) {
    return erro ? (
      <div className="alert alert-err">
        <p>{erro}</p>
      </div>
    ) : (
      <p className="hint">Carregando entrevista…</p>
    );
  }

  if (!dados.convocado) {
    return (
      <div>
        <h3>Entrevista técnica</h3>
        <p className="hint">
          Este candidato não está convocado para a entrevista (exige habilitação, AC ≥ 35 pontos e estar entre os 3 melhores por vaga — itens 6.4.4 e 6.5.1).
        </p>
      </div>
    );
  }

  const somaTotal = COMPETENCIAS.reduce((s, c) => s + (Number(notas[c.chave]) || 0), 0);

  return (
    <div>
      <h3>Entrevista técnica</h3>
      <p className="hint">
        A entrevista acontece fora do sistema. Lance aqui a ficha de cada avaliador da banca (Anexo II): nota inteira por competência e justificativa
        obrigatória. A nota da entrevista (ET) é a <b>média</b> das notas totais dos avaliadores (item 6.5.5).
      </p>

      <div className="tabela-wrap" style={{ margin: "12px 0" }}>
        <table className="tabela">
          <thead>
            <tr>
              <th>AC (máx. 60)</th>
              <th>Entrevista — ET (máx. {TOTAL_ENTREVISTA})</th>
              <th>PF = AC + ET (máx. 100)</th>
              <th>Fichas lançadas</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td className="col-total">{fmtNota(dados.ac)}</td>
              <td className="col-total">{fmtNota(dados.et)}</td>
              <td className="col-total">{fmtNota(dados.pf)}</td>
              <td>
                {dados.n_fichas} (a banca exige no mínimo {BANCA_MINIMA}, item 6.5.2)
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      {!dados.banca_completa && dados.n_fichas > 0 ? (
        <div className="alert alert-warn">
          <p>Banca incompleta: o edital exige no mínimo {BANCA_MINIMA} avaliadores. A média acima é provisória.</p>
        </div>
      ) : null}
      {dados.abaixo_do_corte ? (
        <div className="alert alert-err">
          <p>
            Nota da entrevista abaixo de {CORTE_ENTREVISTA} pontos (item 6.5.7): o edital prevê eliminação. O sistema só sinaliza — a decisão e a
            motivação são da Comissão.
          </p>
        </div>
      ) : null}

      {dados.fichas.map((f) => (
        <details key={f.id} className="card" style={{ margin: "8px 0" }}>
          <summary style={{ cursor: "pointer", fontWeight: 700 }}>
            {f.avaliador_nome} — {f.total} de {TOTAL_ENTREVISTA} pontos
          </summary>
          <div style={{ marginTop: 10 }}>
            {COMPETENCIAS.map((c) => {
              const nota = f[`nota_${c.chave}` as keyof FichaEntrevista] as number;
              const just = f[`just_${c.chave}` as keyof FichaEntrevista] as string;
              return (
                <p key={c.chave} style={{ margin: "6px 0" }}>
                  <b>{c.rotulo}:</b> {nota}/{c.peso} <span className="hint">({faixa(nota, c.peso)})</span>
                  <br />
                  <span className="hint">{just}</span>
                </p>
              );
            })}
            <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
              <button type="button" className="btn btn-sm" onClick={() => editar(f)}>
                Corrigir esta ficha
              </button>
              <button type="button" className="btn btn-sm btn-ghost" onClick={() => remover(f)}>
                Remover
              </button>
            </div>
          </div>
        </details>
      ))}

      <div id="form-ficha" className="card" style={{ marginTop: 12 }}>
        <h4 style={{ marginTop: 0 }}>Lançar ficha de um avaliador</h4>
        <p className="hint">Se o mesmo nome já tem ficha para este candidato, ela é substituída (correção).</p>
        <div className="field" style={{ marginBottom: 12 }}>
          <label htmlFor="avaliador">Nome do avaliador</label>
          <input id="avaliador" value={avaliador} onChange={(e) => setAvaliador(e.target.value)} placeholder="Nome completo do membro da banca" />
        </div>
        {COMPETENCIAS.map((c) => {
          const n = Number(notas[c.chave]);
          const ok = notas[c.chave] !== "" && Number.isInteger(n) && n >= 0 && n <= c.peso;
          return (
            <div key={c.chave} className="field" style={{ marginBottom: 14 }}>
              <label htmlFor={`n-${c.chave}`}>
                {c.rotulo} <span className="hint">(peso {c.peso})</span>
                {ok ? <span className="hint"> — {faixa(n, c.peso)}</span> : null}
              </label>
              <input
                id={`n-${c.chave}`}
                type="number"
                min={0}
                max={c.peso}
                step={1}
                inputMode="numeric"
                value={notas[c.chave]}
                onChange={(e) => setNotas({ ...notas, [c.chave]: e.target.value })}
                style={{ maxWidth: 120 }}
                placeholder={`0 a ${c.peso}`}
              />
              <textarea
                aria-label={`Justificativa — ${c.rotulo}`}
                value={justs[c.chave]}
                onChange={(e) => setJusts({ ...justs, [c.chave]: e.target.value })}
                placeholder="Justificativa (o que o candidato respondeu que sustenta a nota)"
                style={{ marginTop: 6, minHeight: 64 }}
              />
            </div>
          );
        })}
        <p className="hint">
          Total desta ficha: <b>{somaTotal}</b> de {TOTAL_ENTREVISTA}
        </p>
        {erro ? (
          <div className="alert alert-err">
            <p>{erro}</p>
          </div>
        ) : null}
        {aviso ? (
          <div className="alert alert-ok">
            <p>{aviso}</p>
          </div>
        ) : null}
        <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
          <button type="button" className="btn btn-primary" disabled={salvando} onClick={salvar}>
            {salvando ? "Salvando…" : "Salvar ficha"}
          </button>
          <button type="button" className="btn btn-ghost" onClick={limpar} disabled={salvando}>
            Limpar
          </button>
        </div>
      </div>
    </div>
  );
}
