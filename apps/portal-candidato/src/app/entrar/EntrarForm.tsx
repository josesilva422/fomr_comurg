"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { emailValido } from "@/lib/validacao";

type Etapa = "email" | "codigo";

function mensagemDeErro(e: { message?: string; status?: number; code?: string }): string {
  const t = `${e.message ?? ""} ${e.code ?? ""}`.toLowerCase();
  if (e.status === 429 || t.includes("rate limit") || t.includes("over_email_send_rate_limit"))
    return "Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente de novo.";
  if (t.includes("not authorized"))
    return "Este endereço ainda não pode receber o código (ambiente de testes). Fale com a Comissão.";
  if (t.includes("expired") || t.includes("invalid") || t.includes("token"))
    return "Código inválido ou expirado. Confira os números ou peça um novo código.";
  return "Não foi possível concluir agora. Tente novamente em instantes.";
}

export function EntrarForm() {
  const router = useRouter();
  const supabase = createClient();
  const [etapa, setEtapa] = useState<Etapa>("email");
  const [email, setEmail] = useState("");
  const [codigo, setCodigo] = useState("");
  const [erro, setErro] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [espera, setEspera] = useState(0);

  useEffect(() => {
    if (espera <= 0) return;
    const id = setTimeout(() => setEspera((s) => s - 1), 1000);
    return () => clearTimeout(id);
  }, [espera]);

  async function enviarCodigo(e?: React.FormEvent) {
    e?.preventDefault();
    setErro("");
    const limpo = email.trim().toLowerCase();
    if (!emailValido(limpo)) return setErro("Informe um e-mail válido.");
    setEnviando(true);
    const { error } = await supabase.auth.signInWithOtp({ email: limpo, options: { shouldCreateUser: true } });
    setEnviando(false);
    if (error) return setErro(mensagemDeErro(error));
    setEmail(limpo);
    setCodigo("");
    setEtapa("codigo");
    setEspera(30);
  }

  async function confirmarCodigo(e: React.FormEvent) {
    e.preventDefault();
    setErro("");
    const token = codigo.replace(/\D/g, "");
    if (token.length < 6) return setErro("Digite o código recebido por e-mail.");
    setEnviando(true);
    const { error } = await supabase.auth.verifyOtp({ email, token, type: "email" });
    if (error) {
      setEnviando(false);
      return setErro(mensagemDeErro(error));
    }
    router.replace("/inscricao");
    router.refresh();
  }

  return (
    <section className="card narrow">
      {etapa === "email" ? (
        <form onSubmit={enviarCodigo} noValidate>
          <header className="step-head">
            <p className="eyebrow">Acesso do candidato</p>
            <h2>Entre com seu e-mail</h2>
            <p className="lead">
              Enviaremos um código de acesso para o seu e-mail. Não é preciso criar senha. Use um e-mail que você consulta
              com frequência: ele será usado para os avisos do processo seletivo.
            </p>
          </header>
          <div className={`field${erro ? " invalid" : ""}`}>
            <label htmlFor="email">E-mail</label>
            <input
              id="email"
              type="email"
              autoComplete="email"
              inputMode="email"
              placeholder="voce@exemplo.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoFocus
            />
            {erro ? <p className="err" role="alert">{erro}</p> : null}
          </div>
          <div className="acoes-form">
            <button type="submit" className="btn btn-primary" disabled={enviando}>
              {enviando ? <span className="spin" aria-hidden /> : null} Enviar código
            </button>
          </div>
        </form>
      ) : (
        <form onSubmit={confirmarCodigo} noValidate>
          <header className="step-head">
            <p className="eyebrow">Confirme seu acesso</p>
            <h2>Digite o código</h2>
            <p className="lead">
              Enviamos um código para <b>{email}</b>. Ele vale por 15 minutos. Se não encontrar, olhe também a caixa de spam.
            </p>
          </header>
          <div className={`field${erro ? " invalid" : ""}`}>
            <label htmlFor="codigo">Código de acesso</label>
            <input
              id="codigo"
              className="codigo"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={10}
              placeholder="000000"
              value={codigo}
              onChange={(e) => setCodigo(e.target.value.replace(/\D/g, ""))}
              autoFocus
            />
            {erro ? <p className="err" role="alert">{erro}</p> : null}
          </div>
          <div className="acoes-form" style={{ justifyContent: "space-between" }}>
            <button type="button" className="btn btn-ghost" onClick={() => { setEtapa("email"); setErro(""); }}>
              ← Trocar e-mail
            </button>
            <span style={{ display: "flex", gap: 8 }}>
              <button type="button" className="btn" disabled={espera > 0 || enviando} onClick={() => enviarCodigo()}>
                {espera > 0 ? `Reenviar em ${espera}s` : "Reenviar código"}
              </button>
              <button type="submit" className="btn btn-primary" disabled={enviando}>
                {enviando ? <span className="spin" aria-hidden /> : null} Entrar
              </button>
            </span>
          </div>
        </form>
      )}
    </section>
  );
}
