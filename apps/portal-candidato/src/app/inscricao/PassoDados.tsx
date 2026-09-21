"use client";

import { useState } from "react";
import { Campo } from "@/components/Campo";
import { CampoArquivo } from "@/components/CampoArquivo";
import { Pendencias } from "@/components/Pendencias";
import { createClient } from "@/lib/supabase/client";
import { NACIONALIDADES, type Nacionalidade } from "@/lib/tipos";
import { NASCIMENTO_MAXIMO, cpfValido, mascaraCPF, mascaraTelefone, somenteDigitos, traduzirErro } from "@/lib/validacao";
import { docsDoTipo, type Contexto } from "./contexto";

export function PassoDados({ ctx }: { ctx: Contexto }) {
  const { candidato, inscricao } = ctx;
  const [nome, setNome] = useState(candidato?.nome ?? "");
  const [cpf, setCpf] = useState(candidato ? mascaraCPF(candidato.cpf) : "");
  const [nasc, setNasc] = useState(candidato?.data_nascimento ?? "");
  const [tel, setTel] = useState(candidato ? mascaraTelefone(candidato.telefone) : "");
  const [nac, setNac] = useState<Nacionalidade | "">(candidato?.nacionalidade ?? "");
  const [erros, setErros] = useState<Record<string, string>>({});
  const [erroGeral, setErroGeral] = useState("");
  const [tentou, setTentou] = useState(false);
  // pendências ao vivo: some da lista assim que o candidato resolve (o banco recalcula a cada mudança)
  const faltam = tentou ? ctx.pendencias.filter((p) => p.etapa === 1) : [];
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
    setTentou(false);
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
      : await supabase.from("candidatos").insert({ user_id: ctx.userId, ...dados });
    if (error) {
      setSalvando(false);
      return setErroGeral(traduzirErro(error));
    }
    const pend = await ctx.recarregar();
    setSalvando(false);
    setTentou(true);
    if (!pend.some((p) => p.etapa === 1)) ctx.irPara(2);
  }

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
        <Campo id="nome" rotulo="Nome completo" obrigatorio erro={erros.nome} className="full">
          <input id="nome" value={nome} onChange={(e) => setNome(e.target.value)} autoComplete="name" placeholder="Sem abreviações" />
        </Campo>
        <Campo id="cpf" rotulo="CPF" obrigatorio erro={erros.cpf} dica="Só é possível uma inscrição por CPF.">
          <input id="cpf" value={cpf} onChange={(e) => setCpf(mascaraCPF(e.target.value))} inputMode="numeric" placeholder="000.000.000-00" />
        </Campo>
        <Campo id="nasc" rotulo="Data de nascimento" obrigatorio erro={erros.nasc}>
          <input id="nasc" type="date" value={nasc} onChange={(e) => setNasc(e.target.value)} min="1920-01-01" />
        </Campo>
        <Campo id="email" rotulo="E-mail" dica="É o e-mail da sua conta. Os avisos do processo seletivo serão enviados para ele.">
          <input id="email" value={ctx.email} readOnly disabled />
        </Campo>
        <Campo id="tel" rotulo="Telefone com DDD" obrigatorio erro={erros.tel}>
          <input id="tel" value={tel} onChange={(e) => setTel(mascaraTelefone(e.target.value))} inputMode="tel" placeholder="(62) 90000-0000" />
        </Campo>
        <Campo id="nac" rotulo="Nacionalidade" obrigatorio erro={erros.nac} className="full">
          <select id="nac" value={nac} onChange={(e) => setNac(e.target.value as Nacionalidade)}>
            <option value="">Selecione</option>
            {NACIONALIDADES.map((n) => (
              <option key={n.valor} value={n.valor}>
                {n.rotulo}
              </option>
            ))}
          </select>
        </Campo>
      </div>

      <h3 style={{ marginTop: 30 }}>Documentos pessoais</h3>
      {inscricao ? (
        <>
          <p className="sub">Formatos aceitos: PDF, JPG ou PNG, legíveis, até 10 MB por arquivo.</p>
          <div className="grid">
            <div className="full">
              <CampoArquivo
                inscricaoId={inscricao.id}
                tipo="identidade"
                rotulo="Documento de identidade (frente e verso)"
                dica="RG, CNH ou outro documento oficial com foto. Pode enviar frente e verso em arquivos separados."
                obrigatorio
                multiplo
                docs={docsDoTipo(ctx.documentos, "identidade")}
                aoMudar={ctx.recarregar}
              />
            </div>
            <div className="full">
              <CampoArquivo
                inscricaoId={inscricao.id}
                tipo="cpf"
                rotulo="Comprovante de CPF"
                dica="Só é necessário se o número do CPF não aparecer no documento de identidade."
                multiplo
                docs={docsDoTipo(ctx.documentos, "cpf")}
                aoMudar={ctx.recarregar}
              />
            </div>
          </div>
        </>
      ) : (
        <div className="alert alert-info">
          <p>Salve seus dados pessoais para liberar o envio dos documentos.</p>
        </div>
      )}

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
