"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

interface Convite {
  id: string;
  email: string;
  convidado_por_nome: string;
  criado_em: string;
  expira_em: string;
  situacao: "pendente" | "aceito" | "expirado" | "cancelado";
  usado_em: string | null;
}

const SITUACAO: Record<string, { rotulo: string; classe: string }> = {
  pendente: { rotulo: "Pendente", classe: "pill-muted" },
  aceito: { rotulo: "Aceito", classe: "pill-ok" },
  expirado: { rotulo: "Expirado", classe: "pill-err" },
  cancelado: { rotulo: "Cancelado", classe: "pill-muted" },
};
const fmtData = (v: string | null) => (v ? new Date(v).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" }) : "—");

// Convites para novos usuários do painel. O formulário só aparece para quem tem permissão de convidar (o banco confere de novo).
export function ConvitesSecao() {
  const [pode, setPode] = useState(false);
  const [convites, setConvites] = useState<Convite[] | null>(null);
  const [versao, setVersao] = useState(0);
  const [email, setEmail] = useState("");
  const [msg, setMsg] = useState<{ tipo: "ok" | "err"; texto: string; link?: string } | null>(null);
  const [enviando, setEnviando] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    supabase
      .schema("painel")
      .rpc("posso_convidar")
      .then(({ data }: { data: boolean | null }) => setPode(!!data));
    supabase
      .schema("painel")
      .rpc("listar_convites")
      .then(({ data }: { data: Convite[] | null }) => setConvites(data ?? []));
  }, [versao]);

  async function convidar(e: React.FormEvent) {
    e.preventDefault();
    setMsg(null);
    setEnviando(true);
    const r = await fetch("/api/painel/convites", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email }),
    });
    const j = await r.json();
    setEnviando(false);
    if (!r.ok) return setMsg({ tipo: "err", texto: j.erro || "Não foi possível criar o convite." });
    setEmail("");
    setVersao((v) => v + 1);
    setMsg(
      j.enviado
        ? { tipo: "ok", texto: "Convite enviado por e-mail. O link vale por 12 horas." }
        : { tipo: "ok", texto: "Convite criado, mas o e-mail não pôde ser enviado por aqui. Envie este link à pessoa (vale 12 horas, uso único):", link: j.link },
    );
  }

  return (
    <div style={{ marginTop: 32 }}>
      <h3>Convites</h3>
      {pode ? (
        <form onSubmit={convidar} noValidate style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "flex-end", margin: "12px 0" }}>
          <div className="field" style={{ margin: 0, flex: "1 1 260px" }}>
            <label htmlFor="conv-email">E-mail da pessoa a convidar</label>
            <input id="conv-email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="pessoa@exemplo.com" />
          </div>
          <button type="submit" className="btn btn-primary" disabled={enviando || !email.trim()}>
            {enviando ? <span className="spin" aria-hidden /> : null} Enviar convite
          </button>
        </form>
      ) : (
        <p className="hint">Você não tem permissão para convidar novos usuários.</p>
      )}
      {msg ? (
        <div className={`alert ${msg.tipo === "ok" ? "alert-ok" : ""}`} style={{ margin: "8px 0" }}>
          <p className={msg.tipo === "err" ? "err" : undefined} role="alert">
            {msg.texto}
          </p>
          {msg.link ? (
            <p>
              <input readOnly value={msg.link} style={{ width: "100%" }} onFocus={(e) => e.currentTarget.select()} />
            </p>
          ) : null}
        </div>
      ) : null}

      {!convites ? null : convites.length === 0 ? (
        <p className="hint">Nenhum convite emitido ainda.</p>
      ) : (
        <div className="tabela-wrap">
          <table className="tabela">
            <thead>
              <tr>
                <th>E-mail</th>
                <th>Convidado por</th>
                <th>Enviado em</th>
                <th>Validade</th>
                <th>Situação</th>
              </tr>
            </thead>
            <tbody>
              {convites.map((c) => (
                <tr key={c.id}>
                  <td>{c.email}</td>
                  <td>{c.convidado_por_nome}</td>
                  <td>{fmtData(c.criado_em)}</td>
                  <td>{fmtData(c.expira_em)}</td>
                  <td>
                    <span className={`pill ${SITUACAO[c.situacao].classe}`}>{SITUACAO[c.situacao].rotulo}</span>
                    {c.usado_em ? <div className="hint">em {fmtData(c.usado_em)}</div> : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
