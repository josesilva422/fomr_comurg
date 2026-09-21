import Link from "next/link";
import { TemaBotao } from "./TemaBotao";

export function Cabecalho({ email, periodo }: { email?: string | null; periodo?: string }) {
  return (
    <header className="site-header">
      <div className="wrap">
        <Link href="/" className="brand" style={{ textDecoration: "none", color: "inherit" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="brand-logo" src="/logo-comurg.jpg" alt="Logotipo da COMURG" />
          <div>
            <strong>PSS COMURG 2026</strong>
            <small>Processo Seletivo Simplificado · Analista de Governança</small>
          </div>
        </Link>
        <div className="header-right">
          <TemaBotao />
          {periodo ? (
            <div className="period">
              <i /> {periodo}
            </div>
          ) : null}
          {email ? (
            <form action="/auth/sair" method="post">
              <button type="submit" className="theme-btn" title={`Conectado como ${email}`}>
                Sair
              </button>
            </form>
          ) : null}
        </div>
      </div>
    </header>
  );
}
