"use client";

import { useRef, useState } from "react";
import { Campo } from "@/components/Campo";
import { CampoArquivo } from "@/components/CampoArquivo";
import { StatusAutoSalvar } from "@/components/StatusAutoSalvar";
import { useAutoSalvar } from "@/lib/auto-salvar";
import { createClient } from "@/lib/supabase/client";
import type { CursoDeclarado, TipoCurso, TipoDocumento, TipoTitulo, Titulo } from "@/lib/tipos-inscricao";
import { traduzirErro } from "@/lib/validacao";
import type { Contexto, RascunhoCurso, RascunhoTitulo } from "./contexto";

const DATA_PUBLICACAO = "2026-09-28";
const DATA_ENCERRAMENTO = "2026-10-13";

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
  aoCriar,
  numero,
}: {
  ctx: Contexto;
  titulo?: Titulo;
  /** Só usado quando `titulo` não é passado (cartão novo): pré-preenche a partir da leitura do currículo. */
  valoresIniciais?: RascunhoTitulo;
  aoFechar?: () => void;
  /** Cartão novo: avisa o id criado no primeiro salvamento automático (a lista não o mostra em dobro). */
  aoCriar?: (id: string) => void;
  numero: number;
}) {
  const [tipo, setTipo] = useState<TipoTitulo | "">(titulo?.tipo ?? valoresIniciais?.tipo ?? "");
  const [nome, setNome] = useState(titulo?.denominacao ?? valoresIniciais?.denominacao ?? "");
  const [inst, setInst] = useState(titulo?.instituicao ?? valoresIniciais?.instituicao ?? "");
  const [carga, setCarga] = useState(titulo ? String(titulo.carga_horaria) : (valoresIniciais?.carga_horaria ?? ""));
  const [data, setData] = useState(titulo?.data_conclusao ?? valoresIniciais?.data_conclusao ?? "");
  const [vindoDoCV] = useState(!titulo && Boolean(valoresIniciais));
  const [erroGeral, setErroGeral] = useState("");
  const [ocupado, setOcupado] = useState(false);
  const [confirmando, setConfirmando] = useState(false);
  // Cartão novo: id criado no primeiro salvamento automático (daí em diante, grava por atualização).
  const [idSalvo, setIdSalvo] = useState<string | null>(null);
  const idRef = useRef<string | null>(titulo?.id ?? null);
  const itemId = titulo?.id ?? idSalvo;

  const erros: Record<string, string> = {};
  if (!tipo) erros.tipo = "Selecione o tipo de título.";
  if (nome.trim().length < 3) erros.nome = "Informe a denominação do curso.";
  if (inst.trim().length < 2) erros.inst = "Informe a instituição.";
  const c = Number(carga);
  if (!Number.isInteger(c) || c <= 0) erros.carga = "Informe a carga horária em horas.";
  if (!data) erros.data = "Informe a data de conclusão.";
  else if (data > DATA_ENCERRAMENTO) erros.data = "A conclusão não pode ser depois do encerramento das inscrições.";
  const pronto = Object.keys(erros).length === 0;
  const assinatura = JSON.stringify([tipo, nome.trim(), inst.trim(), carga, data]);

  const avisos: string[] = [];
  if (tipo === "especializacao" && Number(carga) > 0 && Number(carga) < 360)
    avisos.push("Especialização com menos de 360 horas não é aceita nem pontua.");
  if (data && data > DATA_PUBLICACAO) avisos.push("Concluído depois de 28/09/2026 (publicação do edital): não pontua na análise curricular.");

  async function salvar(): Promise<boolean> {
    setErroGeral("");
    const dados = { tipo, denominacao: nome.trim(), instituicao: inst.trim(), carga_horaria: Number(carga), data_conclusao: data };
    const supabase = createClient();
    if (idRef.current) {
      const { error } = await supabase.from("titulos_declarados").update(dados).eq("id", idRef.current);
      if (error) {
        setErroGeral(traduzirErro(error));
        return false;
      }
    } else {
      const { data: criado, error } = await supabase
        .from("titulos_declarados")
        .insert({ inscricao_id: ctx.inscricao!.id, ...dados })
        .select("id")
        .single();
      if (error || !criado) {
        setErroGeral(error ? traduzirErro(error) : "Não foi possível salvar.");
        return false;
      }
      idRef.current = criado.id as string;
      setIdSalvo(idRef.current);
      aoCriar?.(idRef.current);
    }
    await ctx.recarregar();
    return true;
  }
  const { estado, descartar } = useAutoSalvar({ assinatura, pronto, jaSalvo: Boolean(titulo), salvar });

  async function remover() {
    descartar();
    if (!itemId) return aoFechar?.();
    setOcupado(true);
    const supabase = createClient();
    await supabase.from("documentos").update({ ativo: false }).eq("titulo_id", itemId).eq("ativo", true);
    const { error } = await supabase.from("titulos_declarados").delete().eq("id", itemId);
    if (error) setErroGeral(traduzirErro(error));
    await ctx.recarregar();
    setOcupado(false);
    if (!error) aoFechar?.();
  }

  return (
    <div className="item">
      <div className="item-head">
        <div>
          <strong className="item-title">Título {numero}</strong>
          {vindoDoCV ? <span className="badge badge-warn">Do currículo — confira os dados</span> : null}
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
          <button type="button" className="btn btn-quiet" disabled={ocupado} onClick={() => (itemId ? setConfirmando(true) : void remover())}>
            Remover
          </button>
        )}
      </div>
      <div className="grid">
        <Campo id={`t-tipo-${numero}`} rotulo="Tipo de título" obrigatorio>
          <select id={`t-tipo-${numero}`} value={tipo} onChange={(e) => setTipo(e.target.value as TipoTitulo | "")}>
            <option value="">Selecione</option>
            <option value="especializacao">Especialização / MBA (lato sensu)</option>
            <option value="mestrado">Mestrado</option>
            <option value="doutorado">Doutorado</option>
          </select>
        </Campo>
        <Campo id={`t-nome-${numero}`} rotulo="Denominação do curso" obrigatorio>
          <input id={`t-nome-${numero}`} value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Nome como consta no certificado" />
        </Campo>
        <Campo id={`t-inst-${numero}`} rotulo="Instituição" obrigatorio>
          <input id={`t-inst-${numero}`} value={inst} onChange={(e) => setInst(e.target.value)} placeholder="Instituição credenciada pelo MEC" />
        </Campo>
        <Campo id={`t-carga-${numero}`} rotulo="Carga horária (horas)" obrigatorio>
          <input id={`t-carga-${numero}`} type="number" min={1} inputMode="numeric" value={carga} onChange={(e) => setCarga(e.target.value)} placeholder="Ex.: 420" />
        </Campo>
        <Campo id={`t-data-${numero}`} rotulo="Data de conclusão" obrigatorio>
          <input id={`t-data-${numero}`} type="date" value={data} max={DATA_ENCERRAMENTO} onChange={(e) => setData(e.target.value)} />
        </Campo>
      </div>
      {avisos.length ? <p className="soft">{avisos.join(" ")}</p> : null}
      {erroGeral && estado !== "erro" ? (
        <div className="alert alert-err" role="alert">
          <p>{erroGeral}</p>
        </div>
      ) : null}

      <StatusAutoSalvar estado={estado} faltando={Object.values(erros)} erro={erroGeral} />

      {itemId ? (
        <div style={{ marginTop: 14 }}>
          <CampoArquivo
            inscricaoId={ctx.inscricao!.id}
            tipo={tipo ? DOC_TITULO[tipo] : "diploma_pos"}
            rotulo="Certificado ou diploma"
            dica="Com nome do candidato, denominação, carga horária e data de conclusão."
            obrigatorio
            multiplo
            referencia={{ titulo_id: itemId }}
            docs={ctx.documentos.filter((d) => d.titulo_id === itemId)}
            aoMudar={ctx.recarregar}
          />
        </div>
      ) : (
        <p className="hint" style={{ marginTop: 10 }}>
          O envio do certificado é liberado assim que o título for salvo (preencha os campos acima).
        </p>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ Cursos e certificações */

export function CartaoCurso({
  ctx,
  curso,
  valoresIniciais,
  aoFechar,
  aoCriar,
  numero,
}: {
  ctx: Contexto;
  curso?: CursoDeclarado;
  /** Só usado quando `curso` não é passado (cartão novo): pré-preenche a partir da leitura do currículo. */
  valoresIniciais?: RascunhoCurso;
  aoFechar?: () => void;
  /** Cartão novo: avisa o id criado no primeiro salvamento automático (a lista não o mostra em dobro). */
  aoCriar?: (id: string) => void;
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
  const [erroGeral, setErroGeral] = useState("");
  const [ocupado, setOcupado] = useState(false);
  const [confirmando, setConfirmando] = useState(false);
  // Cartão novo: id criado no primeiro salvamento automático (daí em diante, grava por atualização).
  const [idSalvo, setIdSalvo] = useState<string | null>(null);
  const idRef = useRef<string | null>(curso?.id ?? null);
  const itemId = curso?.id ?? idSalvo;

  const erros: Record<string, string> = {};
  if (!tipo) erros.tipo = "Selecione o tipo (curso ou certificação).";
  if (nome.trim().length < 3) erros.nome = "Informe a denominação.";
  if (inst.trim().length < 2) erros.inst = "Informe a instituição ou entidade.";
  const c = Number(carga);
  if (tipo === "curso" && (!Number.isInteger(c) || c <= 0)) erros.carga = "Informe a carga horária expressa no certificado.";
  if (tipo === "certificacao" && !cred.trim()) erros.cred = "Informe o número da credencial ativa.";
  if (tipo === "certificacao" && !codigo.trim()) erros.codigo = "Informe o código de verificação.";
  if (!data) erros.data = "Informe a data de conclusão ou emissão.";
  else if (data > DATA_ENCERRAMENTO) erros.data = "A data não pode ser depois do encerramento das inscrições.";
  const pronto = Object.keys(erros).length === 0;
  const assinatura = JSON.stringify([tipo, nome.trim(), inst.trim(), carga, data, cred.trim(), codigo.trim()]);

  const avisos: string[] = [];
  if (tipo === "curso" && Number(carga) > 0 && Number(carga) < 20) avisos.push("Cursos com menos de 20 horas não pontuam.");
  if (data && data > DATA_PUBLICACAO) avisos.push("Concluído depois de 28/09/2026 (publicação do edital): não pontua.");

  async function salvar(): Promise<boolean> {
    setErroGeral("");
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
    if (idRef.current) {
      const { error } = await supabase.from("cursos_declarados").update(dados).eq("id", idRef.current);
      if (error) {
        setErroGeral(traduzirErro(error));
        return false;
      }
    } else {
      const { data: criado, error } = await supabase
        .from("cursos_declarados")
        .insert({ inscricao_id: ctx.inscricao!.id, ...dados })
        .select("id")
        .single();
      if (error || !criado) {
        setErroGeral(error ? traduzirErro(error) : "Não foi possível salvar.");
        return false;
      }
      idRef.current = criado.id as string;
      setIdSalvo(idRef.current);
      aoCriar?.(idRef.current);
    }
    await ctx.recarregar();
    return true;
  }
  const { estado, descartar } = useAutoSalvar({ assinatura, pronto, jaSalvo: Boolean(curso), salvar });

  async function remover() {
    descartar();
    if (!itemId) return aoFechar?.();
    setOcupado(true);
    const supabase = createClient();
    await supabase.from("documentos").update({ ativo: false }).eq("curso_id", itemId).eq("ativo", true);
    const { error } = await supabase.from("cursos_declarados").delete().eq("id", itemId);
    if (error) setErroGeral(traduzirErro(error));
    await ctx.recarregar();
    setOcupado(false);
    if (!error) aoFechar?.();
  }

  return (
    <div className="item">
      <div className="item-head">
        <div>
          <strong className="item-title">Item {numero}</strong>
          {vindoDoCV ? <span className="badge badge-warn">Do currículo — confira os dados</span> : null}
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
          <button type="button" className="btn btn-quiet" disabled={ocupado} onClick={() => (itemId ? setConfirmando(true) : void remover())}>
            Remover
          </button>
        )}
      </div>
      <div className="grid">
        <Campo id={`c-tipo-${numero}`} rotulo="Tipo" obrigatorio>
          <select id={`c-tipo-${numero}`} value={tipo} onChange={(e) => setTipo(e.target.value as TipoCurso | "")}>
            <option value="">Selecione</option>
            <option value="curso">Curso complementar</option>
            <option value="certificacao">Certificação profissional</option>
          </select>
        </Campo>
        <Campo id={`c-nome-${numero}`} rotulo="Denominação" obrigatorio>
          <input id={`c-nome-${numero}`} value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Nome como consta no certificado" />
        </Campo>
        <Campo id={`c-inst-${numero}`} rotulo="Instituição ou entidade certificadora" obrigatorio>
          <input id={`c-inst-${numero}`} value={inst} onChange={(e) => setInst(e.target.value)} />
        </Campo>
        <Campo id={`c-carga-${numero}`} rotulo="Carga horária (horas)" obrigatorio={tipo === "curso"}>
          <input id={`c-carga-${numero}`} type="number" min={1} inputMode="numeric" value={carga} onChange={(e) => setCarga(e.target.value)} placeholder="Ex.: 40" />
        </Campo>
        <Campo id={`c-data-${numero}`} rotulo="Data de conclusão ou emissão" obrigatorio>
          <input id={`c-data-${numero}`} type="date" value={data} max={DATA_ENCERRAMENTO} onChange={(e) => setData(e.target.value)} />
        </Campo>
      </div>
      {tipo === "certificacao" ? (
        <div className="grid" style={{ marginTop: 16 }}>
          <Campo id={`c-cred-${numero}`} rotulo="Número da credencial ativa" obrigatorio>
            <input id={`c-cred-${numero}`} value={cred} onChange={(e) => setCred(e.target.value)} />
          </Campo>
          <Campo id={`c-cod-${numero}`} rotulo="Código de verificação" obrigatorio dica="Certificação vencida ou sem credencial e código válidos não pontua.">
            <input id={`c-cod-${numero}`} value={codigo} onChange={(e) => setCodigo(e.target.value)} />
          </Campo>
        </div>
      ) : null}
      {avisos.length ? <p className="soft">{avisos.join(" ")}</p> : null}
      {erroGeral && estado !== "erro" ? (
        <div className="alert alert-err" role="alert">
          <p>{erroGeral}</p>
        </div>
      ) : null}

      <StatusAutoSalvar estado={estado} faltando={Object.values(erros)} erro={erroGeral} />

      {itemId ? (
        <div style={{ marginTop: 14 }}>
          <CampoArquivo
            inscricaoId={ctx.inscricao!.id}
            tipo={tipo === "certificacao" ? "certificacao_profissional" : "certificado_curso"}
            rotulo="Certificado"
            dica="Com nome do candidato, denominação, carga horária (cursos) e data."
            obrigatorio
            multiplo
            referencia={{ curso_id: itemId }}
            docs={ctx.documentos.filter((d) => d.curso_id === itemId)}
            aoMudar={ctx.recarregar}
          />
        </div>
      ) : (
        <p className="hint" style={{ marginTop: 10 }}>
          O envio do certificado é liberado assim que o item for salvo (preencha os campos acima).
        </p>
      )}
    </div>
  );
}
