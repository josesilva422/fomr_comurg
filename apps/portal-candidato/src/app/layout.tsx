import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Inscrição · PSS COMURG 2026",
  description: "Portal de inscrição do Processo Seletivo Simplificado COMURG 2026 (Analista de Governança).",
  icons: { icon: "/logo-comurg.jpg" },
  robots: { index: true, follow: true },
};

// Aplica o tema salvo antes da primeira pintura (evita "piscar" claro/escuro).
const temaInicial = `try{var t=localStorage.getItem('pss-tema');if(t==='light'||t==='dark')document.documentElement.setAttribute('data-theme',t)}catch(e){}`;

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="pt-BR" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: temaInicial }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
