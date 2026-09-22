"use client";

import { useState } from "react";
import { Campo } from "@/components/Campo";
import { CampoArquivo } from "@/components/CampoArquivo";
import { createClient } from "@/lib/supabase/client";
import type { CursoDeclarado, TipoCurso, TipoDocumento, TipoTitulo, Titulo } from "@/lib/tipos-inscricao";
import { traduzirErro } from "@/lib/validacao";
import type { Contexto, RascunhoCurso, RascunhoTitulo } from "./contexto";

const DATA_PUBLICACAO = "2026-09-24";
const DATA_ENCERRAMENTO = "2026-10-07";

const DOC_TITULO: Record<TipoTitulo, TipoDocumento> = {
  especializacao: "diploma_pos",
  mestrado: "diploma_mestrado",
  doutorado: "diploma_doutorado",
};

/* ------------------------------------------------------------------ Pós-graduação */

export function CartaoTitulo({
  ctx,
  titulo,
  valoresIniciais,
  aoFechar,
  numero,
}: {
  ctx: Contexto;
  titulo?: Titulo;
  /** Só usado quando `titulo` não é passado (cartão novo): pré-preenche a partir da leitura do currículo. */
  valoresIniciais?: RascunhoTitulo;
  aoFechar?: () => void;
  numero: number;
}) {
  const [tipo, setTipo] = useState<TipoTitulo | "">(titulo?.tipo ?? valoresIniciais?.tipo ?? "");
  const [nome, setNome] = useState(titulo?.denominacao ?? valoresIniciais?.denominacao ?? "");
  const [inst, setInst] = useState(titulo?.instituicao ?? valoresIniciais?.instituicao ?? "");
  const [carga, setCarga] = useState(titulo ? String(titulo.carga_horaria) : (valoresIniciais?.carga_horaria ?? ""));
  const [data, setData] = useState(titulo?.data_conclusao ?? valoresIniciais?.data_conclusao ?? "");
  const [vindoDoCV] = useState(!titulo && Boolean(valoresIniciais));
  const [erros, setErros] = useState<Record<string, string>>({});
  const [erroGeral, setErroGeral] = useState("");
  const [ocupado, setOcupado] = useState(false);
  const [confirmando, setConfirmando] = useState(false);

  const avisos: string[] = [];
  if (tipo === "especializacao" && Number(carga) > 0 && Number(carga) < 360)
    avisos.push("Especialização com menos de 360 horas não é aceita nem pontua.");
  if (data && data > DATA_PUBLICACAO) avisos.push("Concluído depois de 24/09/2026 (publicação do edital): não pontua na análise curricular.");

  async function salvar() {
    setErroGeral("");
    const e: Record<string, string> = {};
    if (!tipo) e.tipo = "Selecione uma opção.";
    if (nome.trim().length < 3) e.nome = "Informe a denominação do curso.";
    if (inst.trim().length < 2) e.inst = "Informe a instituição.";
    const c = Number(carga);
    if (!Number.isInteger(c) || c <= 0) e.carga = "Informe a carga horária em horas.";
    if (!data) e.data = "Informe a data de conclusão.";
    else if (data > DATA_ENCERRAMENTO) e.data = "A conclusão não pode ser depois do encerramento das inscrições.";
    setErros(e);
    if (Object.keys(e).length) return;
    setOcupado(true);
    const dados = { tipo, denominacao: nome.trim(), instituicao: inst.trim(), carga_horaria: c, data_conclusao: data };
    const supabase = createClient();
    const { error } = titulo
      ? await supabase.from("titulos_declarados").update(dados).eq("id", titulo.id)
      : await supabase.from("titulos_declarados").insert({ inscricao_id: ctx.inscricao!.id, ...dados });
    if (error) {
      setOcupado(false);
      return setErroGeral(traduzirErro(error));
    }
    await ctx.recarregar();
    setOcupado(false);
    aoFechar?.();
  }

  async function remover() {
    if (!titulo) return aoFechar?.();
    setOcupado(true);
    const supabase = createClient();
    await supabase.from("documentos").update({ ativo: false }).eq("titulo_id", titulo.id).eq("ativo", true);
    const { error } = await supabase.from("titulos_declarados").delete().eq("id", titulo.id);
    if (error) setErroGeral(traduzirErro(error));
    await ctx.recarregar();
    setOcupado(false);
  }

  return (
    <div className="item">
      <div className="item-head">
        <div>
          <strong className="item-title">Título {numero}</strong>
          {vindoDoCV ? <span className="badge badge-warn">Do currículo — confira antes de salvar</span> : null}
        </div>
        {confirmando ? (
          <span style={{ display: "flex", gap: 6, alignItems: "center", fontSize: 14 }}>
            Remover este título?
            <button type="button" className="btn btn-quiet" disabled={ocupado} onClick={() => void remover()}>
              Sim, remover
            </button>
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setConfirmando(false)}>
              Cancelar
            </button>
          </span>
        ) : (
          <button type="button" className="btn btn-quiet" disabled={ocupado} onClick={() => (titulo ? setConfirmando(true) : aoFechar?.())}>
            Remover
          </button>
        )}
      </div>
      <div className="grid">
        <Campo id={`t-tipo-${numero}`} rotulo="Tipo de título" obrigatorio erro={erros.tipo}>
          <select id={`t-tipo-${numero}`} value={tipo} onChange={(e) => setTipo(e.target.value as TipoTitulo | "")}>
            <option value="">Selecione</option>
            <option value="especializacao">Especialização / MBA (lato sensu)</option>
            <option value="mestrado">Mestrado</option>
            <option value="doutorado">Doutorado</option>
          </select>
        </Campo>
        <Campo id={`t-nome-${numero}`} rotulo="Denominação do curso" obrigatorio erro={erros.nome}>
          <input id={`t-nome-${numero}`} value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Nome como consta no certificado" />
        </Campo>
        <Campo id={`t-inst-${numero}`} rotulo="Instituição" obrigatorio erro={erros.inst}>
          <input id={`t-inst-${numero}`} value={inst} onChange={(e) => setInst(e.target.value)} placeholder="Instituição credenciada pelo MEC" />
        </Campo>
        <Campo id={`t-carga-${numero}`} rotulo="Carga horária (horas)" obrigatorio erro={erros.carga}>
          <input id={`t-carga-${numero}`} type="number" min={1} inputMode="numeric" value={carga} onChange={(e) => setCarga(e.target.value)} placeholder="Ex.: 420" />
        </Campo>
        <Campo id={`t-data-${numero}`} rotulo="Data de conclusão" obrigatorio erro={erros.data}>
          <input id={`t-data-${numero}`} type="date" value={data} max={DATA_ENCERRAMENTO} onChange={(e) => setData(e.target.value)} />
        </Campo>
      </div>
      {avisos.length ? <p className="soft">{avisos.join(" ")}</p> : null}
      {erroGeral ? (
        <div className="alert alert-err" role="alert">
          <p>{erroGeral}</p>
        </div>
      ) : null}

      {titulo ? (
        <div style={{ marginTop: 14 }}>
          <CampoArquivo
            inscricaoId={ctx.inscricao!.id}
            tipo={tipo ? DOC_TITULO[tipo] : "diploma_pos"}
            rotulo="Certificado ou diploma"
            dica="Com nome do candidato, denominação, carga horária e data de conclusão."
            obrigatorio
            multiplo
            referencia={{ titulo_id: titulo.id }}
            docs={ctx.documentos.filter((d) => d.titulo_id === titulo.id)}
            aoMudar={ctx.recarregar}
          />
        </div>
      ) : (
        <p className="hint" style={{ marginTop: 10 }}>
          Salve o título para liberar o envio do certificado.
        </p>
      )}
      <div className="acoes-form" style={{ marginTop: 12 }}>
        <button type="button" className="btn btn-sm" disabled={ocupado} onClick={() => void salvar()}>
          {ocupado ? <span className="spin" aria-hidden /> : null} {titulo ? "Salvar alterações" : "Salvar título"}
        </button>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ Cursos e certificações */

export function CartaoCurso({
  ctx,
  curso,
  valoresIniciais,
  aoFechar,
  numero,
}: {
  ctx: Contexto;
  curso?: CursoDeclarado;
  /** Só usado quando `curso` não é passado (cartão novo): pré-preenche a partir da leitura do currículo. */
  valoresIniciais?: RascunhoCurso;
  aoFechar?: () => void;
  numero: number;
}) {
  const [tipo, setTipo] = useState<TipoCurso | "">(curso?.tipo ?? valoresIniciais?.tipo ?? "");
  const [nome, setNome] = useState(curso?.denominacao ?? valoresIniciais?.denominacao ?? "");
  const [inst, setInst] = useState(curso?.instituicao ?? valoresIniciais?.instituicao ?? "");
  const [carga, setCarga] = useState(curso?.carga_horaria ? String(curso.carga_horaria) : (valoresIniciais?.carga_horaria ?? ""));
  const [data, setData] = useState(curso?.data_conclusao ?? valoresIniciais?.data_conclusao ?? "");
  const [cred, setCred] = useState(curso?.numero_credencial ?? valoresIniciais?.numero_credencial ?? "");
  const [codigo, setCodigo] = useState(curso?.codigo_verificacao ?? valoresIniciais?.codigo_verificacao ?? "");
  const [vindoDoCV] = useState(!curso && Boolean(valoresIniciais));
  const [erros, setErros] = useState<Record<string, string>>({});
  const [erroGeral, setErroGeral] = useState("");
  const [ocupado, setOcupado] = useState(false);
  const [confirmando, setConfirmando] = useState(false);

  const avisos: string[] = [];
  if (tipo === "curso" && Number(carga) > 0 && Number(carga) < 20) avisos.push("Cursos com menos de 20 horas não pontuam.");
  if (data && data > DATA_PUBLICACAO) avisos.push("Concluído depois de 24/09/2026 (publicação do edital): não pontua.");

  async function salvar() {
    setErroGeral("");
    const e: Record<string, string> = {};
    if (!tipo) e.tipo = "Selecione uma opção.";
    if (nome.trim().length < 3) e.nome = "Informe a denominação.";
    if (inst.trim().length < 2) e.inst = "Informe a instituição ou entidade.";
    const c = Number(carga);
    if (tipo === "curso" && (!Number.isInteger(c) || c <= 0)) e.carga = "Informe a carga horária expressa no certificado.";
    if (tipo === "certificacao" && !cred.trim()) e.cred = "Informe o número da credencial ativa.";
    if (tipo === "certificacao" && !codigo.trim()) e.codigo = "Informe o código de verificação.";
    if (!data) e.data = "Informe a data de conclusão ou emissão.";
    else if (data > DATA_ENCERRAMENTO) e.data = "A data não pode ser depois do encerramento das inscrições.";
    setErros(e);
    if (Object.keys(e).length) return;
    setOcupado(true);
    const dados = {
      tipo,
      denominacao: nome.trim(),
      instituicao: inst.trim(),
      carga_horaria: Number.isInteger(c) && c > 0 ? c : null,
      data_conclusao: data,
      numero_credencial: tipo === "certificacao" ? cred.trim() : null,
      codigo_verificacao: tipo === "certificacao" ? codigo.trim() : null,
    };
    const supabase = createClient();
    const { error } = curso
      ? await supabase.from("cursos_declarados").update(dados).eq("id", curso.id)
      : await supabase.from("cursos_declarados").insert({ inscricao_id: ctx.inscricao!.id, ...dados });
    if (error) {
      setOcupado(false);
      return setErroGeral(traduzirErro(error));
    }
    await ctx.recarregar();
    setOcupado(false);
    aoFechar?.();
  }

  async function remover() {
    if (!curso) return aoFechar?.();
    setOcupado(true);
    const supabase = createClient();
    await supabase.from("documentos").update({ ativo: false }).eq("curso_id", curso.id).eq("ativo", true);
    const { error } = await supabase.from("cursos_declarados").delete().eq("id", curso.id);
    if (error) setErroGeral(traduzirErro(error));
    await ctx.recarregar();
    setOcupado(false);
  }

  return (
    <div className="item">
      <div className="item-head">
        <div>
          <strong className="item-title">Item {numero}</strong>
          {vindoDoCV ? <span className="badge badge-warn">Do currículo — confira antes de salvar</span> : null}
        </div>
        {confirmando ? (
          <span style={{ display: "flex", gap: 6, alignItems: "center", fontSize: 14 }}>
            Remover este item?
            <button type="button" className="btn btn-quiet" disabled={ocupado} onClick={() => void remover()}>
              Sim, remover
            </button>
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setConfirmando(false)}>
              Cancelar
            </button>
          </span>
        ) : (
          <button type="button" className="btn btn-quiet" disabled={ocupado} onClick={() => (curso ? setConfirmando(true) : aoFechar?.())}>
            Remover
          </button>
        )}
      </div>
      <div className="grid">
        <Campo id={`c-tipo-${numero}`} rotulo="Tipo" obrigatorio erro={erros.tipo}>
          <select id={`c-tipo-${numero}`} value={tipo} onChange={(e) => setTipo(e.target.value as TipoCurso | "")}>
            <option value="">Selecione</option>
            <option value="curso">Curso complementar</option>
            <option value="certificacao">Certificação profissional</option>
          </select>
        </Campo>
        <Campo id={`c-nome-${numero}`} rotulo="Denominação" obrigatorio erro={erros.nome}>
          <input id={`c-nome-${numero}`} value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Nome como consta no certificado" />
        </Campo>
        <Campo id={`c-inst-${numero}`} rotulo="Instituição ou entidade certificadora" obrigatorio erro={erros.inst}>
          <input id={`c-inst-${numero}`} value={inst} onChange={(e) => setInst(e.target.value)} />
        </Campo>
        <Campo id={`c-carga-${numero}`} rotulo="Carga horária (horas)" obrigatorio={tipo === "curso"} erro={erros.carga}>
          <input id={`c-carga-${numero}`} type="number" min={1} inputMode="numeric" value={carga} onChange={(e) => setCarga(e.target.value)} placeholder="Ex.: 40" />
        </Campo>
        <Campo id={`c-data-${numero}`} rotulo="Data de conclusão ou emissão" obrigatorio erro={erros.data}>
          <input id={`c-data-${numero}`} type="date" value={data} max={DATA_ENCERRAMENTO} onChange={(e) => setData(e.target.value)} />
        </Campo>
      </div>
      {tipo === "certificacao" ? (
        <div className="grid" style={{ marginTop: 16 }}>
          <Campo id={`c-cred-${numero}`} rotulo="Número da credencial ativa" obrigatorio erro={erros.cred}>
            <input id={`c-cred-${numero}`} value={cred} onChange={(e) => setCred(e.target.value)} />
          </Campo>
          <Campo id={`c-cod-${numero}`} rotulo="Código de verificação" obrigatorio erro={erros.codigo} dica="Certificação vencida ou sem credencial e código válidos não pontua.">
            <input id={`c-cod-${numero}`} value={codigo} onChange={(e) => setCodigo(e.target.value)} />
          </Campo>
        </div>
      ) : null}
      {avisos.length ? <p className="soft">{avisos.join(" ")}</p> : null}
      {erroGeral ? (
        <div className="alert alert-err" role="alert">
          <p>{erroGeral}</p>
        </div>
      ) : null}

      {curso ? (
        <div style={{ marginTop: 14 }}>
          <CampoArquivo
            inscricaoId={ctx.inscricao!.id}
            tipo={tipo === "certificacao" ? "certificacao_profissional" : "certificado_curso"}
            rotulo="Certificado"
            dica="Com nome do candidato, denominação, carga horária (cursos) e data."
            obrigatorio
            multiplo
            referencia={{ curso_id: curso.id }}
            docs={ctx.documentos.filter((d) => d.curso_id === curso.id)}
            aoMudar={ctx.recarregar}
          />
        </div>
      ) : (
        <p className="hint" style={{ marginTop: 10 }}>
          Salve o item para liberar o envio do certificado.
        </p>
      )}
      <div className="acoes-form" style={{ marginTop: 12 }}>
        <button type="button" className="btn btn-sm" disabled={ocupado} onClick={() => void salvar()}>
          {ocupado ? <span className="spin" aria-hidden /> : null} {curso ? "Salvar alterações" : "Salvar item"}
        </button>
      </div>
    </div>
  );
}
