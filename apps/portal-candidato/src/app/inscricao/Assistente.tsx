"use client";

import { useEffect, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS, REQUISITOS, VAGAS } from "@/lib/requisitos";
import type { Candidato, Grupo, Inscricao, Nacionalidade, Nivel } from "@/lib/tipos";
import { NACIONALIDADES } from "@/lib/tipos";
import {
  NASCIMENTO_MAXIMO,
  cpfValido,
  mascaraCPF,
  mascaraTelefone,
  somenteDigitos,
  traduzirErro,
} from "@/lib/validacao";

const PASSOS = [
  "Dados pessoais",
  "Grupo e nível",
  "Formação",
  "Experiência",
  "Cotas e isenção",
  "Pagamento (Pix)",
  "Revisão e envio",
] as const;

const EM_BREVE: Record<number, string> = {
  3: "Graduação, diploma, pós-graduação, cursos e certificações, com envio dos documentos.",
  4: "Vínculos de experiência com períodos, contagem sem sobreposição e documentos comprobatórios.",
  5: "Vagas reservadas (pessoa com deficiência e candidatos negros) e pedido de isenção da taxa.",
  6: "Chave Pix, valor da taxa e envio do comprovante de pagamento.",
  7: "Conferência das pendências, declarações e o botão Enviar solicitação.",
};

interface Props {
  userId: string;
  email: string;
  candidato: Candidato | null;
  inscricao: Inscricao | null;
}

export function Assistente({ userId, email, candidato: candInicial, inscricao: inscInicial }: Props) {
  const [candidato, setCandidato] = useState(candInicial);
  const [inscricao, setInscricao] = useState(inscInicial);
  const primeiro = !candInicial ? 1 : !inscInicial?.grupo || !inscInicial?.nivel ? 2 : 3;
  const [passo, setPasso] = useState(primeiro);

  const selada = inscricao != null && inscricao.status !== "rascunho";

  function statusDoPasso(n: number): { classe: string; texto: string } {
    if (n === passo) return { classe: "is-current", texto: "Etapa atual" };
    if (n === 1) return candidato ? { classe: "is-done", texto: "Completa" } : { classe: "", texto: "Pendente" };
    if (n === 2)
      return inscricao?.grupo && inscricao?.nivel ? { classe: "is-done", texto: "Completa" } : { classe: "", texto: "Pendente" };
    return { classe: "", texto: "Em breve" };
  }

  if (selada && inscricao) return <Enviada inscricao={inscricao} candidato={candidato} />;

  const chipVaga =
    inscricao?.grupo || inscricao?.nivel
      ? `${inscricao?.grupo ? GRUPOS[inscricao.grupo].nome : "Grupo —"} · ${inscricao?.nivel ? NIVEIS[inscricao.nivel].nome : "Nível —"}`
      : null;

  return (
    <main className="wrap layout">
      <aside className="rail" aria-label="Etapas da inscrição">
        <div className="rail-compact">
          <div className="rail-compact-top">
            <strong>Etapa {passo} de 7</strong>
            <span>{PASSOS[passo - 1]}</span>
          </div>
          <div className="bar">
            <i style={{ width: `${(passo / 7) * 100}%` }} />
          </div>
        </div>
        <ol className="rail-list">
          {PASSOS.map((nome, i) => {
            const n = i + 1;
            const st = statusDoPasso(n);
            const bloqueado = n > 1 && !candidato;
            return (
              <li key={nome}>
                <button
                  type="button"
                  className={`rail-item ${st.classe}`}
                  disabled={bloqueado}
                  aria-current={n === passo ? "step" : undefined}
                  onClick={() => setPasso(n)}
                >
                  <span className="dot">{st.classe === "is-done" ? "✓" : n}</span>
                  <span className="lbl">
                    {nome}
                    <small>{bloqueado ? "Preencha a etapa 1" : st.texto}</small>
                  </span>
                </button>
              </li>
            );
          })}
        </ol>
        {chipVaga ? (
          <div className="rail-vaga">
            <b>Sua vaga</b>
            {chipVaga}
          </div>
        ) : null}
        <p className="rail-help">Você pode sair e continuar depois: o rascunho fica salvo. Depois de enviar, a inscrição é definitiva.</p>
      </aside>

      <div>
        {passo === 1 && (
          <PassoDados
            userId={userId}
            email={email}
            candidato={candidato}
            onSalvo={(c, i) => {
              setCandidato(c);
              setInscricao(i);
              setPasso(2);
            }}
          />
        )}
        {passo === 2 && candidato && inscricao && (
          <PassoVaga
            inscricao={inscricao}
            onSalvo={(i) => {
              setInscricao(i);
              setPasso(3);
            }}
          />
        )}
        {passo >= 3 && (
          <section className="card step">
            <header className="step-head">
              <p className="eyebrow">Etapa {passo} de 7</p>
              <h2>{PASSOS[passo - 1]}</h2>
              <p className="lead">{EM_BREVE[passo]}</p>
            </header>
            <div className="em-breve">Esta etapa será liberada na próxima entrega do sistema.</div>
          </section>
        )}
        <div className="actions" style={{ position: "static", background: "transparent", border: 0, padding: 0, marginTop: 18 }}>
          <button type="button" className="btn btn-ghost" style={{ visibility: passo === 1 ? "hidden" : "visible" }} onClick={() => setPasso((p) => Math.max(1, p - 1))}>
            ← Voltar
          </button>
        </div>
      </div>
    </main>
  );
}

/* ------------------------------------------------------------------ Etapa 1 */

function PassoDados({
  userId,
  email,
  candidato,
  onSalvo,
}: {
  userId: string;
  email: string;
  candidato: Candidato | null;
  onSalvo: (c: Candidato, i: Inscricao) => void;
}) {
  const [nome, setNome] = useState(candidato?.nome ?? "");
  const [cpf, setCpf] = useState(candidato ? mascaraCPF(candidato.cpf) : "");
  const [nasc, setNasc] = useState(candidato?.data_nascimento ?? "");
  const [tel, setTel] = useState(candidato ? mascaraTelefone(candidato.telefone) : "");
  const [nac, setNac] = useState<Nacionalidade | "">(candidato?.nacionalidade ?? "");
  const [erros, setErros] = useState<Record<string, string>>({});
  const [erroGeral, setErroGeral] = useState("");
  const [salvando, setSalvando] = useState(false);

  function validar() {
    const e: Record<string, string> = {};
    if (!/^\S+(\s+\S+)+$/.test(nome.trim())) e.nome = "Informe o nome completo, com sobrenome.";
    if (!cpfValido(cpf)) e.cpf = "CPF inválido. Confira os números digitados.";
    if (!nasc) e.nasc = "Informe a data de nascimento.";
    else if (nasc > NASCIMENTO_MAXIMO) e.nasc = "É preciso ter 18 anos completos até 07/10/2026 (encerramento das inscrições).";
    else if (nasc < "1920-01-01") e.nasc = "Data inválida.";
    const t = somenteDigitos(tel);
    if (t.length < 10 || t.length > 11) e.tel = "Informe o DDD e o número. Ex.: (62) 90000-0000.";
    if (!nac) e.nac = "Selecione uma opção.";
    setErros(e);
    return Object.keys(e).length === 0;
  }

  async function salvar(ev: React.FormEvent) {
    ev.preventDefault();
    setErroGeral("");
    if (!validar()) return;
    setSalvando(true);
    const supabase = createClient();
    const dados = {
      nome: nome.trim().replace(/\s+/g, " "),
      cpf: somenteDigitos(cpf),
      telefone: somenteDigitos(tel),
      data_nascimento: nasc,
      nacionalidade: nac,
    };
    const { error } = candidato
      ? await supabase.from("candidatos").update(dados).eq("id", candidato.id)
      : await supabase.from("candidatos").insert({ user_id: userId, ...dados });
    if (error) {
      setSalvando(false);
      return setErroGeral(traduzirErro(error));
    }
    const { data: c } = await supabase.from("candidatos").select("*").maybeSingle();
    const { data: i } = await supabase.from("inscricoes").select("*").maybeSingle();
    setSalvando(false);
    if (!c || !i) return setErroGeral("Cadastro salvo, mas não foi possível carregar a inscrição. Recarregue a página.");
    onSalvo(c as Candidato, i as Inscricao);
  }

  const campo = (id: string, rotulo: string, children: React.ReactNode, dica?: string, cls = "") => (
    <div className={`field ${cls}${erros[id] ? " invalid" : ""}`}>
      <label htmlFor={id}>
        {rotulo} <b className="req" aria-hidden="true">*</b>
      </label>
      {children}
      {dica ? <p className="hint">{dica}</p> : null}
      {erros[id] ? (
        <p className="err" role="alert">
          {erros[id]}
        </p>
      ) : null}
    </div>
  );

  return (
    <form className="card step" onSubmit={salvar} noValidate>
      <header className="step-head">
        <p className="eyebrow">Etapa 1 de 7</p>
        <h2>Dados pessoais</h2>
        <p className="lead">
          Preencha exatamente como está no seu documento de identidade. Esses dados serão conferidos com o comprovante de
          Pix e com a documentação enviada.
        </p>
      </header>
      <div className="grid">
        {campo(
          "nome",
          "Nome completo",
          <input id="nome" value={nome} onChange={(e) => setNome(e.target.value)} autoComplete="name" placeholder="Sem abreviações" />,
          undefined,
          "full",
        )}
        {campo("cpf", "CPF", <input id="cpf" value={cpf} onChange={(e) => setCpf(mascaraCPF(e.target.value))} inputMode="numeric" placeholder="000.000.000-00" />, "Só é possível uma inscrição por CPF.")}
        {campo("nasc", "Data de nascimento", <input id="nasc" type="date" value={nasc} onChange={(e) => setNasc(e.target.value)} min="1920-01-01" />)}
        <div className="field">
          <label htmlFor="email">E-mail</label>
          <input id="email" value={email} readOnly disabled />
          <p className="hint">É o e-mail da sua conta. Os avisos do processo seletivo serão enviados para ele.</p>
        </div>
        {campo("tel", "Telefone com DDD", <input id="tel" value={tel} onChange={(e) => setTel(mascaraTelefone(e.target.value))} inputMode="tel" placeholder="(62) 90000-0000" />)}
        {campo(
          "nac",
          "Nacionalidade",
          <select id="nac" value={nac} onChange={(e) => setNac(e.target.value as Nacionalidade)}>
            <option value="">Selecione</option>
            {NACIONALIDADES.map((n) => (
              <option key={n.valor} value={n.valor}>
                {n.rotulo}
              </option>
            ))}
          </select>,
          undefined,
          "full",
        )}
      </div>
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

/* ------------------------------------------------------------------ Etapa 2 */

function PassoVaga({ inscricao, onSalvo }: { inscricao: Inscricao; onSalvo: (i: Inscricao) => void }) {
  const [grupo, setGrupo] = useState<Grupo | "">(inscricao.grupo ?? "");
  const [nivel, setNivel] = useState<Nivel | "">(inscricao.nivel ?? "");
  const [cursos, setCursos] = useState<string[] | null>(null);
  const [erros, setErros] = useState<Record<string, string>>({});
  const [erroGeral, setErroGeral] = useState("");
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
    const e: Record<string, string> = {};
    if (!grupo) e.grupo = "Selecione uma opção.";
    if (!nivel) e.nivel = "Selecione uma opção.";
    setErros(e);
    if (Object.keys(e).length) return;
    setSalvando(true);
    const supabase = createClient();
    const { error } = await supabase.from("inscricoes").update({ grupo, nivel }).eq("id", inscricao.id);
    if (error) {
      setSalvando(false);
      return setErroGeral(traduzirErro(error));
    }
    const { data } = await supabase.from("inscricoes").select("*").maybeSingle();
    setSalvando(false);
    if (data) onSalvo(data as Inscricao);
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
          Escolha o grupo e o nível da vaga. Cada candidato pode fazer <b>uma única inscrição</b>, em um grupo e um nível
          (item 4.5 do edital).
        </p>
      </header>

      <fieldset className={`group${erros.grupo ? " invalid" : ""}`}>
        <legend>
          Grupo <b className="req" aria-hidden="true">*</b>
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
        {erros.grupo ? <p className="err" role="alert">{erros.grupo}</p> : null}
      </fieldset>

      <fieldset className={`group${erros.nivel ? " invalid" : ""}`}>
        <legend>
          Nível <b className="req" aria-hidden="true">*</b>
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
        {erros.nivel ? <p className="err" role="alert">{erros.nivel}</p> : null}
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
                        <span className="chip" key={c}>{c}</span>
                      ))}
                    </div>
                    {engs.length > 0 ? (
                      <details>
                        <summary>Ver as {engs.length} engenharias aceitas</summary>
                        <div className="chips" style={{ marginTop: 8 }}>
                          {engs.map((c) => (
                            <span className="chip" key={c}>{c}</span>
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
            <Linha t="Experiência mínima" d={<b>{NIVEIS[nivel].minAnos} {NIVEIS[nivel].minAnos > 1 ? "anos" : "ano"}</b>} />
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

function Linha({ t, d }: { t: string; d: React.ReactNode }) {
  return (
    <div className="kv">
      <dt>{t}</dt>
      <dd>{d}</dd>
    </div>
  );
}

/* ------------------------------------------------------------------ Inscrição enviada (selada) */

function Enviada({ inscricao, candidato }: { inscricao: Inscricao; candidato: Candidato | null }) {
  const protocolo = `PSS-2026-${inscricao.id.slice(0, 8).toUpperCase()}`;
  const quando = inscricao.submetida_em
    ? new Intl.DateTimeFormat("pt-BR", { dateStyle: "long", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(inscricao.submetida_em))
    : "";
  return (
    <main className="wrap" style={{ padding: "24px 16px 64px" }}>
      <section className="card success">
        <div className="ok" aria-hidden>✓</div>
        <h2>Solicitação enviada</h2>
        <p className="lead" style={{ margin: "8px auto 0" }}>
          {candidato ? `${candidato.nome.split(" ")[0]}, s` : "S"}ua inscrição foi recebida e está bloqueada para alterações. Guarde o número do protocolo.
        </p>
        <div className="protocolo">{protocolo}</div>
        {quando ? <p style={{ color: "var(--muted)", fontSize: 14 }}>Enviada em {quando}</p> : null}
        <p style={{ color: "var(--muted)", fontSize: 14, marginTop: 6 }}>
          Situação: <b>{inscricao.status === "aguardando_isencao" ? "aguardando análise do pedido de isenção" : "recebida, aguardando homologação"}</b>
        </p>
      </section>
    </main>
  );
}
