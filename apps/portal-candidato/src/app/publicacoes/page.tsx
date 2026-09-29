import Link from "next/link";
import { Cabecalho } from "@/components/Cabecalho";
import { ItemComunicado, ItemDocumento } from "@/components/PortalPublicacoes";
import { createClient } from "@/lib/supabase/server";
import { GRUPOS_DOCUMENTOS, ordenarDocumentos, type PublicacaoPublica } from "@/lib/portal";

export const metadata = { title: "Publicações · PSS COMURG 2026" };

const fmt = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "America/Sao_Paulo" });
const EMAIL_OFICIAL = "pss2026comurg@comurg.com.br";

const FILTROS = [
  { chave: "todas", rotulo: "Todas" },
  { chave: "comunicados", rotulo: "Comunicados" },
  ...GRUPOS_DOCUMENTOS.map((g) => ({ chave: g.chave, rotulo: g.titulo })),
];

// Histórico completo dos atos publicados na plataforma (edital, item 13.2), com filtro por tipo.
export default async function Publicacoes({ searchParams }: { searchParams: Promise<{ tipo?: string }> }) {
  const { tipo: tipoParam } = await searchParams;
  const tipo = FILTROS.some((f) => f.chave === tipoParam) ? tipoParam! : "todas";

  const supabase = await createClient();
  const [{ data: pubs }, { data: per }] = await Promise.all([supabase.rpc("listar_publicacoes"), supabase.rpc("periodo_inscricoes")]);
  const publicacoes = (pubs as PublicacaoPublica[] | null) ?? [];
  const periodo = Array.isArray(per) && per.length ? (per[0] as { abertura: string; encerramento: string; agora: string }) : null;
  const agora = periodo ? new Date(periodo.agora) : new Date();
  const situacao = periodo ? `Inscrições: ${fmt.format(new Date(periodo.abertura))} a ${fmt.format(new Date(periodo.encerramento))}` : undefined;

  const comunicados = publicacoes
    .filter((p) => p.categoria === "comunicado")
    .sort((a, b) => new Date(b.publicado_em).getTime() - new Date(a.publicado_em).getTime());
  const grupos = GRUPOS_DOCUMENTOS.map((g) => ({ ...g, itens: ordenarDocumentos(publicacoes.filter((p) => g.categorias.includes(p.categoria))) }));
  const contagem = (chave: string) =>
    chave === "todas" ? publicacoes.length : chave === "comunicados" ? comunicados.length : (grupos.find((g) => g.chave === chave)?.itens.length ?? 0);

  const mostraComunicados = (tipo === "todas" || tipo === "comunicados") && comunicados.length > 0;
  const gruposVisiveis = grupos.filter((g) => (tipo === "todas" || tipo === g.chave) && g.itens.length > 0);

  return (
    <>
      <Cabecalho periodo={situacao} />
      <main className="wrap portal-main" style={{ paddingTop: 28 }}>
        <div>
          <Link href="/" className="portal-voltar">
            ← Voltar à página inicial
          </Link>
          <h1 className="portal-pagina-titulo">Publicações</h1>
          <p className="portal-pagina-sub">
            Todos os atos do Processo Seletivo Simplificado 2026 publicados nesta plataforma: edital, retificações, resultados, convocações,
            anexos e comunicados (item 13.2 do edital).
          </p>
        </div>

        <nav className="portal-filtros" aria-label="Filtrar publicações">
          {FILTROS.filter((f) => f.chave === "todas" || contagem(f.chave) > 0).map((f) => (
            <Link
              key={f.chave}
              href={f.chave === "todas" ? "/publicacoes" : `/publicacoes?tipo=${f.chave}`}
              className={`portal-filtro${tipo === f.chave ? " is-ativo" : ""}`}
              aria-current={tipo === f.chave ? "page" : undefined}
            >
              {f.rotulo} <span>{contagem(f.chave)}</span>
            </Link>
          ))}
        </nav>

        {!mostraComunicados && gruposVisiveis.length === 0 ? <p className="portal-vazio">Nenhuma publicação até o momento.</p> : null}

        {mostraComunicados ? (
          <section className="portal-bloco" aria-labelledby="t-com">
            <header className="portal-bloco-topo">
              <h2 id="t-com">Comunicados</h2>
            </header>
            <ul className="portal-lista">
              {comunicados.map((c) => (
                <ItemComunicado key={c.id} c={c} agora={agora} />
              ))}
            </ul>
          </section>
        ) : null}

        {gruposVisiveis.map((g) => (
          <section key={g.chave} className="portal-bloco" aria-labelledby={`t-${g.chave}`}>
            <header className="portal-bloco-topo">
              <h2 id={`t-${g.chave}`}>{g.titulo}</h2>
            </header>
            <ul className="portal-docs">
              {g.itens.map((d) => (
                <ItemDocumento key={d.id} d={d} agora={agora} mostrarCategoria={g.chave === "edital"} />
              ))}
            </ul>
          </section>
        ))}
      </main>
      <footer className="portal-rodape">
        <div className="wrap">
          <p>
            <b>Companhia de Urbanização de Goiânia — COMURG</b> · Processo Seletivo Simplificado 2026 · Edital nº 001/2026
          </p>
          <p>
            Comissão Organizadora: <a href={`mailto:${EMAIL_OFICIAL}`}>{EMAIL_OFICIAL}</a>
          </p>
        </div>
      </footer>
    </>
  );
}
