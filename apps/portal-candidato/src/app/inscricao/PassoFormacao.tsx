"use client";

import { useEffect, useState } from "react";
import { Campo } from "@/components/Campo";
import { CampoArquivo } from "@/components/CampoArquivo";
import { Pendencias } from "@/components/Pendencias";
import { createClient } from "@/lib/supabase/client";
import { GRUPOS, NIVEIS, REQUISITOS } from "@/lib/requisitos";
import type { Inscricao } from "@/lib/tipos";
import type { DadosCurriculo } from "@/lib/openai";
import { traduzirErro } from "@/lib/validacao";
import { docsDoTipo, type Contexto, type RascunhoCurso, type RascunhoTitulo } from "./contexto";
import { ImportarCurriculo } from "./ImportarCurriculo";
import { CartaoCurso, CartaoTitulo } from "./ItensFormacao";

type Grau = NonNullable<Inscricao["grau_graduacao"]>;
type Formato = NonNullable<Inscricao["formato_diploma"]>;

export function PassoFormacao({ ctx }: { ctx: Contexto }) {
  const insc = ctx.inscricao!;
  const [curso, setCurso] = useState(insc.curso_graduacao ?? "");
  const [grau, setGrau] = useState<Grau | "">(insc.grau_graduacao ?? "");
  const [instituicao, setInstituicao] = useState(insc.instituicao_graduacao ?? "");
  const [colacao, setColacao] = useState(insc.data_colacao ?? "");
  const [formato, setFormato] = useState<Formato | "">(insc.formato_diploma ?? "");
  const [codigo, setCodigo] = useState(insc.codigo_diploma_digital ?? "");
  const [provisorio, setProvisorio] = useState(insc.diploma_provisorio);
  const [exterior, setExterior] = useState(insc.diploma_exterior);
  const [opcoes, setOpcoes] = useState<string[] | null>(null);
  const [erros, setErros] = useState<Record<string, string>>({});
  const [erroGeral, setErroGeral] = useState("");
  const [tentou, setTentou] = useState(false);
  // pendências ao vivo: some da lista assim que o candidato resolve (o banco recalcula a cada mudança)
  const faltam = tentou ? ctx.pendencias.filter((p) => p.etapa === 3) : [];
  const [salvando, setSalvando] = useState(false);
  // cartões ainda não salvos — os salvos vêm do banco; `valores`, quando presente, vem da leitura do currículo
  const [novosTitulos, setNovosTitulos] = useState<{ chave: number; valores?: RascunhoTitulo }[]>([]);
  const [novosCursos, setNovosCursos] = useState<{ chave: number; valores?: RascunhoCurso }[]>([]);
  const [contador, setContador] = useState(1);

  useEffect(() => {
    if (!insc.grupo || !insc.nivel) return;
    let vivo = true;
    createClient()
      .from("cursos_aceitos")
      .select("curso")
      .eq("grupo", insc.grupo)
      .eq("nivel", insc.nivel)
      .order("curso")
      .then(({ data }: { data: { curso: string }[] | null }) => {
        if (vivo) setOpcoes((data ?? []).map((l) => l.curso));
      });
    return () => {
      vivo = false;
    };
  }, [insc.grupo, insc.nivel]);

  if (!insc.grupo || !insc.nivel) {
    return (
      <section className="card step">
        <header className="step-head">
          <p className="eyebrow">Etapa 3 de 7</p>
          <h2>Formação</h2>
        </header>
        <div className="alert alert-warn">
          <p>Escolha primeiro o grupo e o nível na etapa 2. A lista de graduações aceitas depende dessa escolha.</p>
        </div>
        <div className="acoes-form">
          <button type="button" className="btn btn-primary" onClick={() => ctx.irPara(2)}>
            Ir para a etapa 2
          </button>
        </div>
      </section>
    );
  }

  const req = REQUISITOS[insc.grupo][insc.nivel];
  const engs = (opcoes ?? []).filter((c) => c.startsWith("Engenharia"));
  const base = (opcoes ?? []).filter((c) => !c.startsWith("Engenharia"));

  async function salvar() {
    setErroGeral("");
    setTentou(false);
    const e: Record<string, string> = {};
    if (!curso) e.curso = "Selecione uma opção.";
    if (!grau) e.grau = "Selecione uma opção.";
    if (instituicao.trim().length < 2) e.instituicao = "Informe a instituição de ensino.";
    if (!colacao) e.colacao = "Informe a data da colação de grau.";
    else if (colacao > "2026-10-13") e.colacao = "A colação precisa ter ocorrido até 13/10/2026 (encerramento das inscrições).";
    if (!formato) e.formato = "Selecione uma opção.";
    setErros(e);
    if (Object.keys(e).length) return;
    setSalvando(true);
    const { error } = await createClient()
      .from("inscricoes")
      .update({
        curso_graduacao: curso,
        grau_graduacao: grau,
        instituicao_graduacao: instituicao.trim(),
        data_colacao: colacao,
        formato_diploma: formato,
        codigo_diploma_digital: formato === "digital" ? codigo.trim() : null,
        diploma_provisorio: provisorio,
        diploma_exterior: exterior,
      })
      .eq("id", insc.id);
    if (error) {
      setSalvando(false);
      return setErroGeral(traduzirErro(error));
    }
    const pend = await ctx.recarregar();
    setSalvando(false);
    setTentou(true);
    // No Pleno, a pós pode ser substituída pela experiência (etapa 4): essa pendência não segura o avanço —
    // continua bloqueando o envio final se a equivalência não for comprovada.
    const seguram = pend.filter((p) => p.etapa === 3 && !(p.codigo === "pos_sem_comprovante" && insc.nivel === "pleno"));
    if (seguram.length === 0) ctx.irPara(4);
  }

  const docs = (tipo: string) => docsDoTipo(ctx.documentos, tipo);

  function aplicarLeituraCurriculo(dados: DadosCurriculo) {
    // Graduação: só preenche o que ainda estiver vazio (não sobrescreve o que a pessoa já digitou).
    const g = dados.graduacao;
    if (g) {
      if (!curso && g.curso) {
        const encontrado = (opcoes ?? []).find((o) => o.toLowerCase() === g.curso!.trim().toLowerCase());
        if (encontrado) setCurso(encontrado);
      }
      if (!grau && g.grau) setGrau(g.grau);
      if (!instituicao && g.instituicao) setInstituicao(g.instituicao);
      if (!colacao && g.data_conclusao) setColacao(g.data_conclusao);
    }

    let c = contador;
    const titulosNovos = dados.titulos.map((t) => ({
      chave: c++,
      valores: {
        tipo: t.tipo,
        denominacao: t.denominacao,
        instituicao: t.instituicao,
        carga_horaria: t.carga_horaria != null ? String(t.carga_horaria) : "",
        data_conclusao: t.data_conclusao ?? "",
      } satisfies RascunhoTitulo,
    }));
    const cursosNovos = dados.cursos.map((k) => ({
      chave: c++,
      valores: {
        tipo: k.tipo,
        denominacao: k.denominacao,
        instituicao: k.instituicao,
        carga_horaria: k.carga_horaria != null ? String(k.carga_horaria) : "",
        data_conclusao: k.data_conclusao ?? "",
        numero_credencial: k.numero_credencial ?? "",
        codigo_verificacao: k.codigo_verificacao ?? "",
      } satisfies RascunhoCurso,
    }));
    setContador(c);
    if (titulosNovos.length) setNovosTitulos((l) => [...l, ...titulosNovos]);
    if (cursosNovos.length) setNovosCursos((l) => [...l, ...cursosNovos]);

    if (dados.vinculos.length) {
      ctx.definirRascunhosVinculosCV(
        dados.vinculos.map((v) => ({
          tipo: v.tipo,
          empregador_contratante: v.empregador_contratante,
          cargo: v.cargo,
          inicio: v.inicio ?? "",
          fim: v.ativo ? "" : (v.fim ?? ""),
          ativo: v.ativo,
          descricao: v.descricao,
        })),
      );
    }
  }

  return (
    <section className="card step">
      <header className="step-head">
        <p className="eyebrow">Etapa 3 de 7</p>
        <h2>Formação</h2>
        <p className="lead">
          Informe sua graduação (requisito obrigatório) e, se tiver, pós-graduação, cursos e certificações que possam
          pontuar na análise curricular.
        </p>
      </header>

      <ImportarCurriculo documentoAtual={docs("curriculo_anexo_v")[0]} aoLido={aplicarLeituraCurriculo} aoMudar={ctx.recarregar} />

      <h3>Graduação</h3>
      <p className="sub">
        Curso de graduação aceito para {GRUPOS[insc.grupo].nome} · {NIVEIS[insc.nivel].nome}. Cursos tecnológicos
        (tecnólogo) não são aceitos.
      </p>
      <div className="grid">
        <Campo id="curso" rotulo="Curso de graduação" obrigatorio erro={erros.curso} className="full">
          <select id="curso" value={curso} onChange={(e) => setCurso(e.target.value)}>
            <option value="">{opcoes === null ? "Carregando…" : "Selecione"}</option>
            {base.length ? (
              <optgroup label="Graduações">
                {base.map((c) => (
                  <option key={c}>{c}</option>
                ))}
              </optgroup>
            ) : null}
            {engs.length ? (
              <optgroup label="Engenharias">
                {engs.map((c) => (
                  <option key={c}>{c}</option>
                ))}
              </optgroup>
            ) : null}
          </select>
        </Campo>
        <Campo id="grau" rotulo="Grau" obrigatorio erro={erros.grau}>
          <select id="grau" value={grau} onChange={(e) => setGrau(e.target.value as Grau | "")}>
            <option value="">Selecione</option>
            <option value="bacharelado">Bacharelado</option>
            <option value="licenciatura">Licenciatura</option>
            <option value="tecnologico">Tecnológico (tecnólogo)</option>
          </select>
        </Campo>
        <Campo id="instituicao" rotulo="Instituição de ensino" obrigatorio erro={erros.instituicao}>
          <input id="instituicao" value={instituicao} onChange={(e) => setInstituicao(e.target.value)} placeholder="Nome da instituição" />
        </Campo>
        <Campo id="colacao" rotulo="Data da colação de grau" obrigatorio erro={erros.colacao}>
          <input id="colacao" type="date" value={colacao} max="2026-10-13" onChange={(e) => setColacao(e.target.value)} />
        </Campo>
        <Campo id="formato" rotulo="Formato do diploma" obrigatorio erro={erros.formato}>
          <select id="formato" value={formato} onChange={(e) => setFormato(e.target.value as Formato | "")}>
            <option value="">Selecione</option>
            <option value="fisico">Físico (papel)</option>
            <option value="digital">Digital (com validação eletrônica)</option>
          </select>
        </Campo>
      </div>
      {grau === "tecnologico" ? (
        <div className="alert alert-err">
          <p>
            <b>Curso tecnológico não é aceito</b> em nenhum grupo ou nível. Você pode continuar, mas a
            habilitação tende a ser negada na análise.
          </p>
        </div>
      ) : null}
      {formato === "digital" ? (
        <div className="reveal">
          <Campo id="codigo" rotulo="Código de validação, QR Code ou endereço de verificação (se houver)" erro={erros.codigo} dica="O diploma digital precisa ter um mecanismo de validação de autenticidade: código de validação, assinatura digital, QR Code ou outro mecanismo oficial (item 5.1.2 do edital). Se o seu mostra um código ou link, informe aqui; se a validação é por assinatura digital, pode deixar em branco.">
            <input id="codigo" value={codigo} onChange={(e) => setCodigo(e.target.value)} placeholder="Código ou link de validação" />
          </Campo>
        </div>
      ) : null}

      <div style={{ marginTop: 16 }}>
        <CampoArquivo
          inscricaoId={insc.id}
          tipo="diploma_graduacao"
          rotulo="Diploma de graduação (frente e verso)"
          dica="Legível, com nome, curso, data de colação, instituição e assinatura do responsável institucional."
          obrigatorio
          multiplo
          docs={docs("diploma_graduacao")}
          aoMudar={ctx.recarregar}
        />
      </div>

      <div style={{ marginTop: 16, display: "grid", gap: 8 }}>
        <label className="check">
          <input type="checkbox" checked={provisorio} onChange={(e) => setProvisorio(e.target.checked)} />
          Ainda não recebi o diploma (tenho certificado provisório)
        </label>
        {provisorio ? (
          <div className="reveal">
            <CampoArquivo
              inscricaoId={insc.id}
              tipo="historico_escolar"
              rotulo="Histórico escolar com registro de colação de grau"
              dica="Precisa ter o registro de colação de grau e o carimbo da instituição."
              obrigatorio
              multiplo
              docs={docs("historico_escolar")}
              aoMudar={ctx.recarregar}
            />
          </div>
        ) : null}
        <label className="check">
          <input type="checkbox" checked={exterior} onChange={(e) => setExterior(e.target.checked)} />
          Meu diploma foi emitido no exterior
        </label>
        {exterior ? (
          <div className="reveal">
            <CampoArquivo
              inscricaoId={insc.id}
              tipo="revalidacao_diploma"
              rotulo="Comprovante de revalidação do diploma"
              dica="Revalidação por universidade pública brasileira."
              obrigatorio
              multiplo
              docs={docs("revalidacao_diploma")}
              aoMudar={ctx.recarregar}
            />
            <CampoArquivo
              inscricaoId={insc.id}
              tipo="traducao_juramentada"
              rotulo="Tradução juramentada"
              dica="Documentos em língua estrangeira exigem tradução juramentada."
              obrigatorio
              multiplo
              docs={docs("traducao_juramentada")}
              aoMudar={ctx.recarregar}
            />
          </div>
        ) : null}
      </div>

      <hr className="divider" />
      <h3>Pós-graduação, mestrado e doutorado</h3>
      <p className="sub">
        Só pontuam títulos concluídos até a publicação do edital (28/09/2026), de instituição credenciada pelo MEC ou curso
        recomendado pela CAPES, e que <b>não</b> tenham sido usados para cumprir o requisito mínimo.
      </p>
      {req.modo !== "nao" ? (
        <div className="alert alert-info">
          <p>
            {req.modo === "obrig" ? (
              <>
                <b>Pós-graduação obrigatória para este nível.</b> Cadastre abaixo a especialização em {req.pos} e anexe o certificado.
              </>
            ) : (
              <>
                <b>Pós-graduação exigida para este nível</b> ({req.pos}). Cadastre a especialização abaixo e anexe o certificado. Equivalência:{" "}
                {req.equiv} A experiência só vale com os comprovantes anexados na etapa 4
                {insc.grupo === "B" ? ", e a certificação só vale com o certificado anexado" : ""}.
              </>
            )}
          </p>
          <p style={{ marginTop: 6 }}>
            O certificado deve conter seu nome, a denominação do curso, carga horária mínima de 360 horas e a data de conclusão, emitido por instituição
            credenciada pelo MEC ou com curso recomendado pela CAPES. Sem o certificado anexado, não é possível enviar a inscrição
            {req.modo === "equiv" ? " (a não ser que a equivalência esteja comprovada)" : ""}. A especialização usada para cumprir este requisito não
            conta pontos na análise curricular.
          </p>
        </div>
      ) : null}
      <div className="repeater">
        {ctx.titulos.map((t, i) => (
          <CartaoTitulo key={t.id} ctx={ctx} titulo={t} numero={i + 1} />
        ))}
        {novosTitulos.map((n, i) => (
          <CartaoTitulo
            key={`novo-${n.chave}`}
            ctx={ctx}
            numero={ctx.titulos.length + i + 1}
            valoresIniciais={n.valores}
            aoFechar={() => setNovosTitulos((l) => l.filter((x) => x.chave !== n.chave))}
          />
        ))}
      </div>
      <button
        type="button"
        className="btn btn-sm add"
        onClick={() => {
          setNovosTitulos((l) => [...l, { chave: contador }]);
          setContador((c) => c + 1);
        }}
      >
        + Adicionar título
      </button>

      <hr className="divider" />
      <h3>Cursos complementares e certificações</h3>
      <p className="sub">
        Cursos de 20 horas ou mais, com carga horária expressa no certificado, e certificações profissionais reconhecidas
        (PMP, PgMP, PRINCE2, IPMA ou similares).
      </p>
      <div className="repeater">
        {ctx.cursos.map((c, i) => (
          <CartaoCurso key={c.id} ctx={ctx} curso={c} numero={i + 1} />
        ))}
        {novosCursos.map((n, i) => (
          <CartaoCurso
            key={`novo-${n.chave}`}
            ctx={ctx}
            numero={ctx.cursos.length + i + 1}
            valoresIniciais={n.valores}
            aoFechar={() => setNovosCursos((l) => l.filter((x) => x.chave !== n.chave))}
          />
        ))}
      </div>
      <button
        type="button"
        className="btn btn-sm add"
        onClick={() => {
          setNovosCursos((l) => [...l, { chave: contador }]);
          setContador((c) => c + 1);
        }}
      >
        + Adicionar curso ou certificação
      </button>

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
