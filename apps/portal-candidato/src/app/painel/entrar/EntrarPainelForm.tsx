"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Etapa = "senha" | "codigo";

export function EntrarPainelForm() {
  const router = useRouter();
  const [etapa, setEtapa] = useState<Etapa>("senha");
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [codigo, setCodigo] = useState("");
  const [erro, setErro] = useState("");
  const [enviando, setEnviando] = useState(false);

  async function enviarSenha(e: React.FormEvent) {
    e.preventDefault();
    setErro("");
    setEnviando(true);
    const r = await fetch("/api/painel/senha", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: email.trim().toLowerCase(), senha }),
    });
    const j = await r.json();
    setEnviando(false);
    if (!r.ok) return setErro(j.erro || "Não foi possível entrar.");
    setEtapa("codigo");
  }

  async function confirmarCodigo(e: React.FormEvent) {
    e.preventDefault();
    setErro("");
    const token = codigo.replace(/\D/g, "");
    if (token.length < 6) return setErro("Digite o código recebido por e-mail.");
    setEnviando(true);
    const supabase = createClient();
    const { error } = await supabase.auth.verifyOtp({ email: email.trim().toLowerCase(), token, type: "email" });
    if (error) {
      setEnviando(false);
      return setErro("Código inválido ou expirado. Peça um novo.");
    }
    // Libera a sessão no banco (exige a senha conferida antes). Sem isso o painel não abre dados.
    const { data: liberada } = await supabase.schema("painel").rpc("concluir_login");
    if (!liberada) {
      await supabase.auth.signOut();
      setEnviando(false);
      return setErro("Acesso não liberado. Volte e informe e-mail e senha novamente.");
    }
    router.replace("/painel");
    router.refresh();
  }

  return (
    <section className="card narrow">
      <div className="login-passos" aria-hidden="true">
        <span className={etapa === "senha" ? "ativo" : ""} />
        <span className={etapa === "codigo" ? "ativo" : ""} />
      </div>
      {etapa === "senha" ? (
        <form onSubmit={enviarSenha} noValidate>
          <header className="step-head">
            <p className="eyebrow">Área restrita</p>
            <h2>Acesso da Comissão</h2>
            <p className="lead">
              Entre com e-mail e senha. Só contas autorizadas conseguem passar desta etapa; depois, um código
              enviado por e-mail confirma o acesso.
            </p>
          </header>
          <div className={`field${erro ? " invalid" : ""}`}>
            <label htmlFor="p-email">E-mail</label>
            <input id="p-email" type="email" autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} autoFocus />
          </div>
          <div className="field">
            <label htmlFor="p-senha">Senha</label>
            <input id="p-senha" type="password" autoComplete="current-password" value={senha} onChange={(e) => setSenha(e.target.value)} />
          </div>
          {erro ? (
            <p className="err" role="alert">
              {erro}
            </p>
          ) : null}
          <div className="acoes-form">
            <button type="submit" className="btn btn-primary" disabled={enviando}>
              {enviando ? <span className="spin" aria-hidden /> : null} Continuar →
            </button>
          </div>
        </form>
      ) : (
        <form onSubmit={confirmarCodigo} noValidate>
          <header className="step-head">
            <p className="eyebrow">Confirme seu acesso</p>
            <h2>Digite o código</h2>
            <p className="lead">
              Enviamos um código para <b>{email}</b>. Ele vale por 15 minutos.
            </p>
          </header>
          <div className={`field${erro ? " invalid" : ""}`}>
            <label htmlFor="p-codigo">Código de acesso</label>
            <input id="p-codigo" className="codigo" inputMode="numeric" autoComplete="one-time-code" maxLength={10} placeholder="000000" value={codigo} onChange={(e) => setCodigo(e.target.value.replace(/\D/g, ""))} autoFocus />
          </div>
          {erro ? (
            <p className="err" role="alert">
              {erro}
            </p>
          ) : null}
          <div className="acoes-form" style={{ justifyContent: "space-between" }}>
            <button type="button" className="btn btn-ghost" onClick={() => { setEtapa("senha"); setCodigo(""); setErro(""); }}>
              ← Voltar
            </button>
            <button type="submit" className="btn btn-primary" disabled={enviando}>
              {enviando ? <span className="spin" aria-hidden /> : null} Entrar
            </button>
          </div>
        </form>
      )}
    </section>
  );
}
