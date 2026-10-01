"use client";

import { useEffect, useState } from "react";
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
    grupo: "Mais",
    links: [
      { href: "/painel/revisao", rotulo: "Fila de revisão", dica: "Documento ao lado da extração por IA", ativo: (p: string) => p.startsWith("/painel/revisao") },
      { href: "/painel/publicacoes", rotulo: "Publicações e cronograma", dica: "Edital, comunicados e resultados na página inicial", ativo: (p: string) => p.startsWith("/painel/publicacoes") },
      { href: "/painel/usuarios", rotulo: "Usuários do painel", dica: "Quem acessa e quem avaliou", ativo: (p: string) => p.startsWith("/painel/usuarios") },
      { href: "/painel/relatorios", rotulo: "Respostas do formulário", dica: "Baixar em Excel ou PDF", ativo: (p: string) => p.startsWith("/painel/relatorios") },
    ],
  },
] as const;

function grupoAtivo(caminho: string): string | null {
  return ITENS.find((g) => g.links.some((l) => l.ativo(caminho)))?.grupo ?? null;
}

export function PainelNav() {
  const caminho = usePathname();
  // Cada tópico começa fechado, exceto o que contém a página atual.
  const [abertos, setAbertos] = useState<Set<string>>(() => {
    const ativo = grupoAtivo(caminho);
    return new Set(ativo ? [ativo] : []);
  });

  // Ao navegar para uma página de outro tópico, abre-o também (sem fechar os que já estavam abertos).
  useEffect(() => {
    const ativo = grupoAtivo(caminho);
    if (ativo) setAbertos((prev) => (prev.has(ativo) ? prev : new Set(prev).add(ativo)));
  }, [caminho]);

  function alternar(grupo: string) {
    setAbertos((prev) => {
      const novo = new Set(prev);
      if (novo.has(grupo)) novo.delete(grupo);
      else novo.add(grupo);
      return novo;
    });
  }

  return (
    <nav className="painel-nav" aria-label="Menu do painel">
      {ITENS.map((g) => {
        const aberto = abertos.has(g.grupo);
        return (
          <div key={g.grupo} className="painel-nav-grupo">
            <button type="button" className="painel-nav-topico" aria-expanded={aberto} onClick={() => alternar(g.grupo)}>
              <span>{g.grupo}</span>
              <span className={`painel-nav-seta${aberto ? " is-aberta" : ""}`} aria-hidden>
                ›
              </span>
            </button>
            <div className={`painel-nav-links${aberto ? "" : " is-fechado"}`}>
              {g.links.map((l) => (
                <Link key={l.href} href={l.href} className={`painel-nav-link${l.ativo(caminho) ? " is-ativo" : ""}`} aria-current={l.ativo(caminho) ? "page" : undefined}>
                  <span>{l.rotulo}</span>
                  <small>{l.dica}</small>
                </Link>
              ))}
            </div>
          </div>
        );
      })}
      <div className="painel-nav-grupo">
        <p className="painel-nav-titulo">Consulta</p>
        <MotorRegrasBotao />
      </div>
    </nav>
  );
}
