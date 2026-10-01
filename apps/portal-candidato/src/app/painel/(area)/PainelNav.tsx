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
      { href: "/painel/classificacao", rotulo: "Entrevista técnica — geral", dica: "Média (a partir de 3 fichas), PF e posição", ativo: (p: string) => p.startsWith("/painel/classificacao") },
      { href: "/painel/heteroidentificacao", rotulo: "Heteroidentificação", dica: "Decisão motivada (item 10.4)", ativo: (p: string) => p.startsWith("/painel/heteroidentificacao") },
    ],
  },
  {
    grupo: "Avaliador",
    links: [
      { href: "/painel/fichas", rotulo: "Minhas fichas", dica: "Minha nota em cada convocado", ativo: (p: string) => p.startsWith("/painel/fichas") },
    ],
  },
  {
    grupo: "Pré-análise",
    links: [
      { href: "/painel/revisao", rotulo: "Fila de revisão", dica: "Documento ao lado da extração por IA", ativo: (p: string) => p.startsWith("/painel/revisao") },
    ],
  },
  {
    grupo: "Inscrições",
    links: [
      { href: "/painel/isencoes", rotulo: "Isenção da taxa", dica: "Analisar documentos e decidir", ativo: (p: string) => p.startsWith("/painel/isencoes") },
      { href: "/painel/homologacao", rotulo: "Homologação", dica: "Aprovar ou rejeitar inscrições", ativo: (p: string) => p.startsWith("/painel/homologacao") },
      { href: "/painel/cursos-catalogo", rotulo: "Cursos fora do catálogo", dica: "Deliberar sobre a pontuação", ativo: (p: string) => p.startsWith("/painel/cursos-catalogo") },
      { href: "/painel/recursos", rotulo: "Recursos", dica: "Registrar e decidir (recebidos por e-mail)", ativo: (p: string) => p.startsWith("/painel/recursos") },
      { href: "/painel/eliminacoes", rotulo: "Eliminação por fraude", dica: "Falsidade documental (5.5.4, 14.3)", ativo: (p: string) => p.startsWith("/painel/eliminacoes") },
    ],
  },
  {
    grupo: "Portal",
    links: [
      { href: "/painel/publicacoes", rotulo: "Publicações e cronograma", dica: "Edital, comunicados e resultados na página inicial", ativo: (p: string) => p.startsWith("/painel/publicacoes") },
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
