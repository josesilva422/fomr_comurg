"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Etapa = "email" | "codigo" | "dados";

const MENSAGENS: Record<string, string> = {
  convite_invalido: "Convite inválido, já usado ou expirado. Peça um novo a quem convidou.",
  nome_invalido: "Informe o nome completo (nome e sobrenome).",
  cpf_invalido: "CPF inválido.",
  cpf_duplicado: "Este CPF já está cadastrado no painel.",
  senha_fraca: "A senha precisa ter no mínimo 8 caracteres, com letra maiúscula, minúscula, número e caractere especial.",
  ja_e_usuario: "Este e-mail já tem acesso ao painel. Entre pela página de acesso.",
};

// Aceite do convite: e-mail -> código por e-mail -> nome, CPF e senha -> painel.
export function ConviteForm({ token }: { token: string }) {
  const router = useRouter();
  const [etapa, setEtapa] = useState<Etapa>("email");
  const [email, setEmail] = useState("");
  const [codigo, setCodigo] = useState("");
  const [nome, setNome] = useState("");
  const [cpf, setCpf] = useState("");
  const [senha, setSenha] = useState("");
  const [senha2, setSenha2] = useState("");
  const [erro, setErro] = useState("");
  const [enviando, setEnviando] = useState(false);

  if (!token) {
    return (
      <section className="card narrow">
        <header className="step-head">
          <h2>Convite não encontrado</h2>
          <p className="lead">Abra o link completo que você recebeu por e-mail.</p>
        </header>
      </section>
    );
  }

  const limpo = email.trim().toLowerCase();

  async function pedirCodigo(e: React.FormEvent) {
    e.preventDefault();
    setErro("");
    if (!limpo) return setErro("Informe o e-mail que recebeu o convite.");
    setEnviando(true);
    const supabase = createClient();
    const { data: valido } = await supabase.schema("painel").rpc("conferir_convite", { p_token: token, p_email: limpo });
    if (!valido) {
      setEnviando(false);
      return setErro("Convite inválido, expirado, já usado, ou este não é o e-mail convidado.");
    }
    const { error } = await supabase.auth.signInWithOtp({ email: limpo, options: { shouldCreateUser: true } });
    setEnviando(false);
    if (error) return setErro("Não foi possível enviar o código agora. Tente de novo em instantes.");
    setEtapa("codigo");
  }

  async function confirmarCodigo(e: React.FormEvent) {
    e.preventDefault();
    setErro("");
    const digitos = codigo.replace(/\D/g, "");
    if (digitos.length < 6) return setErro("Digite o código recebido por e-mail.");
    setEnviando(true);
    const { error } = await createClient().auth.verifyOtp({ email: limpo, token: digitos, type: "email" });
    setEnviando(false);
    if (error) return setErro("Código inválido ou expirado. Volte e peça um novo.");
    setEtapa("dados");
  }

  async function salvar(e: React.FormEvent) {
    e.preventDefault();
    setErro("");
    if (senha !== senha2) return setErro("As senhas não são iguais.");
    setEnviando(true);
    const supabase = createClient();
    const { error } = await supabase.schema("painel").rpc("aceitar_convite", { p_token: token, p_nome: nome, p_cpf: cpf, p_senha: senha });
    if (error) {
      setEnviando(false);
      const dica = (error as { hint?: string }).hint ?? "";
      return setErro(MENSAGENS[dica] ?? error.message);
    }
    router.replace("/painel");
    router.refresh();
  }

  return (
    <section className="card narrow">
      <div className="login-passos" aria-hidden="true">
        <span className={etapa === "email" ? "ativo" : ""} />
        <span className={etapa === "codigo" ? "ativo" : ""} />
        <span className={etapa === "dados" ? "ativo" : ""} />
      </div>

      {etapa === "email" ? (
        <form onSubmit={pedirCodigo} noValidate>
          <header className="step-head">
            <p className="eyebrow">Convite para o painel</p>
            <h2>Confirme seu e-mail</h2>
            <p className="lead">Informe o e-mail que recebeu o convite. Enviaremos um código para ele.</p>
          </header>
          <div className={`field${erro ? " invalid" : ""}`}>
            <label htmlFor="c-email">E-mail</label>
            <input id="c-email" type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} autoFocus />
          </div>
          {erro ? <p className="err" role="alert">{erro}</p> : null}
          <div className="acoes-form">
            <button type="submit" className="btn btn-primary" disabled={enviando}>
              {enviando ? <span className="spin" aria-hidden /> : null} Enviar código →
            </button>
          </div>
        </form>
      ) : null}

      {etapa === "codigo" ? (
        <form onSubmit={confirmarCodigo} noValidate>
          <header className="step-head">
            <p className="eyebrow">Confirmação</p>
            <h2>Digite o código</h2>
            <p className="lead">Enviamos um código para <b>{limpo}</b>.</p>
          </header>
          <div className={`field${erro ? " invalid" : ""}`}>
            <label htmlFor="c-codigo">Código</label>
            <input id="c-codigo" inputMode="numeric" autoComplete="one-time-code" value={codigo} onChange={(e) => setCodigo(e.target.value)} autoFocus />
          </div>
          {erro ? <p className="err" role="alert">{erro}</p> : null}
          <div className="acoes-form">
            <button type="button" className="btn btn-ghost" onClick={() => { setErro(""); setEtapa("email"); }}>
              ← Voltar
            </button>
            <button type="submit" className="btn btn-primary" disabled={enviando}>
              {enviando ? <span className="spin" aria-hidden /> : null} Confirmar →
            </button>
          </div>
        </form>
      ) : null}

      {etapa === "dados" ? (
        <form onSubmit={salvar} noValidate>
          <header className="step-head">
            <p className="eyebrow">Seu cadastro</p>
            <h2>Preencha seus dados</h2>
            <p className="lead">Estes dados identificam quem acessa o painel e quem lança avaliações. Escolha uma senha para os próximos acessos.</p>
          </header>
          <div className="field">
            <label htmlFor="c-nome">Nome completo</label>
            <input id="c-nome" autoComplete="name" value={nome} onChange={(e) => setNome(e.target.value)} autoFocus />
          </div>
          <div className="field">
            <label htmlFor="c-cpf">CPF</label>
            <input id="c-cpf" inputMode="numeric" value={cpf} onChange={(e) => setCpf(e.target.value)} placeholder="000.000.000-00" />
          </div>
          <div className="field">
            <label htmlFor="c-senha">Senha</label>
            <input id="c-senha" type="password" autoComplete="new-password" value={senha} onChange={(e) => setSenha(e.target.value)} />
            <p className="hint">Mínimo de 8 caracteres, com letra maiúscula, minúscula, número e caractere especial.</p>
          </div>
          <div className="field">
            <label htmlFor="c-senha2">Repita a senha</label>
            <input id="c-senha2" type="password" autoComplete="new-password" value={senha2} onChange={(e) => setSenha2(e.target.value)} />
          </div>
          {erro ? <p className="err" role="alert">{erro}</p> : null}
          <div className="acoes-form">
            <button type="submit" className="btn btn-primary" disabled={enviando}>
              {enviando ? <span className="spin" aria-hidden /> : null} Salvar e entrar →
            </button>
          </div>
        </form>
      ) : null}
    </section>
  );
}
