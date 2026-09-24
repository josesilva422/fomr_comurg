"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { MotorRegrasBotao } from "./MotorRegras";

// Menu lateral do painel. "Classificação final" reúne as duas visões: análise curricular e entrevista técnica.
const ITENS = [
  {
    grupo: "Classificação final",
    links: [
      { href: "/painel", rotulo: "Análise curricular", dica: "Pontuação, habilitação e convocação", ativo: (p: string) => p === "/painel" || p.startsWith("/painel/candidato") },
      { href: "/painel/classificacao", rotulo: "Entrevista técnica", dica: "AC + entrevista = PF e posição", ativo: (p: string) => p.startsWith("/painel/classificacao") },
    ],
  },
  {
    grupo: "Inscrições",
    links: [
      { href: "/painel/isencoes", rotulo: "Isenção da taxa", dica: "Analisar documentos e decidir", ativo: (p: string) => p.startsWith("/painel/isencoes") },
    ],
  },
  {
    grupo: "Acesso",
    links: [
      { href: "/painel/usuarios", rotulo: "Usuários do painel", dica: "Quem acessa e quem avaliou", ativo: (p: string) => p.startsWith("/painel/usuarios") },
    ],
  },
  {
    grupo: "Relatórios",
    links: [
      { href: "/painel/relatorios", rotulo: "Respostas do formulário", dica: "Baixar em Excel ou PDF", ativo: (p: string) => p.startsWith("/painel/relatorios") },
    ],
  },
];

export function PainelNav() {
  const caminho = usePathname();
  return (
    <nav className="painel-nav" aria-label="Menu do painel">
      {ITENS.map((g) => (
        <div key={g.grupo} className="painel-nav-grupo">
          <p className="painel-nav-titulo">{g.grupo}</p>
          {g.links.map((l) => (
            <Link key={l.href} href={l.href} className={`painel-nav-link${l.ativo(caminho) ? " is-ativo" : ""}`} aria-current={l.ativo(caminho) ? "page" : undefined}>
              <span>{l.rotulo}</span>
              <small>{l.dica}</small>
            </Link>
          ))}
        </div>
      ))}
      <div className="painel-nav-grupo">
        <p className="painel-nav-titulo">Consulta</p>
        <MotorRegrasBotao />
      </div>
    </nav>
  );
}
