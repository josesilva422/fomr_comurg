import { CATEGORIAS, ehNovo, tamanhoArquivo, type PublicacaoPublica } from "@/lib/portal";

const fmt = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "America/Sao_Paulo" });

// Itens das listas públicas (página inicial e /publicacoes). O arquivo abre pela rota /publicacoes/{id}, que só entrega
// publicação publicada.

export function ItemComunicado({ c, agora }: { c: PublicacaoPublica; agora: Date }) {
  return (
    <li>
      <div className="portal-lista-data">
        <span>{fmt.format(new Date(c.publicado_em))}</span>
        {ehNovo(c.publicado_em, agora) ? <span className="pill pill-ok">Novo</span> : null}
      </div>
      <div className="portal-lista-corpo">
        <b>{c.titulo}</b>
        {c.texto ? <p>{c.texto}</p> : null}
        {c.tem_arquivo ? (
          <a href={`/publicacoes/${c.id}`} target="_blank" rel="noopener noreferrer">
            Abrir PDF
          </a>
        ) : null}
      </div>
    </li>
  );
}

export function ItemDocumento({ d, agora, mostrarCategoria = true }: { d: PublicacaoPublica; agora: Date; mostrarCategoria?: boolean }) {
  return (
    <li>
      <span className="portal-docs-icone" aria-hidden>
        PDF
      </span>
      <div className="portal-docs-info">
        {mostrarCategoria || ehNovo(d.publicado_em, agora) ? (
          <span className="portal-docs-cat">
            {mostrarCategoria ? CATEGORIAS[d.categoria] : null}
            {ehNovo(d.publicado_em, agora) ? <span className="pill pill-ok">Novo</span> : null}
          </span>
        ) : null}
        <b>{d.titulo}</b>
        {d.texto ? <p>{d.texto}</p> : null}
        <small>
          Publicado em {fmt.format(new Date(d.publicado_em))}
          {d.arquivo_bytes ? ` · ${tamanhoArquivo(d.arquivo_bytes)}` : ""}
        </small>
      </div>
      {d.tem_arquivo ? (
        <a className="btn btn-sm" href={`/publicacoes/${d.id}`} target="_blank" rel="noopener noreferrer">
          Abrir
        </a>
      ) : null}
    </li>
  );
}
