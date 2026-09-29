import Link from "next/link";
import { Cabecalho } from "@/components/Cabecalho";
import { createClient } from "@/lib/supabase/server";
import { GRUPOS, NIVEIS } from "@/lib/requisitos";
import {
  CATEGORIAS,
  ehNovo,
  hojeSP,
  situacaoEtapa,
  tamanhoArquivo,
  textoData,
  type ItemCronograma,
  type PublicacaoPublica,
  type VagaPublica,
} from "@/lib/portal";

const fmt = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "America/Sao_Paulo" });
const fmtHora = new Intl.DateTimeFormat("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" });
const moeda = (v: number) => new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 }).format(v);
const EMAIL_OFICIAL = "pss2026comurg@comurg.com.br";

type Periodo = { abertura: string; encerramento: string; agora: string; aberto: boolean } | null;

// Página inicial pública: site oficial do processo (edital, item 13.2). Ordem por prioridade: situação das inscrições e
// botões (inscrição e edital) → números principais → comunicados e documentos, com "como se inscrever" e contato ao
// lado → vagas → cronograma (Anexo IV, recolhível). Publicações e cronograma vêm do banco (a Comissão publica pelo painel).
export default async function Inicio() {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const logado = Boolean(claims?.claims);
  // Conferido sempre no servidor: quem não é da Comissão nunca recebe esse HTML no navegador.
  const souComissao = logado ? (await supabase.schema("painel").rpc("sou_da_comissao")).data === true : false;
  const [{ data }, { data: pubs }, { data: crono }, { data: vagasDb }] = await Promise.all([
    supabase.rpc("periodo_inscricoes"),
    supabase.rpc("listar_publicacoes"),
    supabase.rpc("cronograma_publico"),
    supabase.rpc("vagas_publicas"),
  ]);
  const periodo: Periodo = Array.isArray(data) && data.length ? data[0] : null;
  const publicacoes = (pubs as PublicacaoPublica[] | null) ?? [];
  const cronograma = (crono as ItemCronograma[] | null) ?? [];
  const vagas = (vagasDb as VagaPublica[] | null) ?? [];

  let situacao = "Inscrições: 05/10 a 20/10/2026";
  let estado: "antes" | "aberto" | "encerrado" = "aberto";
  let detalheEstado = "";
  let aberturaTexto = "";
  if (periodo) {
    const ab = new Date(periodo.abertura);
    const enc = new Date(periodo.encerramento);
    situacao = `Inscrições: ${fmt.format(ab)} a ${fmt.format(enc)}`;
    const agora = new Date(periodo.agora).getTime(); // horário do servidor (banco)
    if (agora < ab.getTime()) {
      estado = "antes";
      aberturaTexto = fmt.format(ab);
      detalheEstado = `Abrem em ${aberturaTexto}`;
    } else if (agora > enc.getTime()) {
      estado = "encerrado";
      detalheEstado = `Encerradas em ${fmt.format(enc)}`;
    } else {
      detalheEstado = `Até ${fmt.format(enc)}, às ${fmtHora.format(enc)}`;
    }
  }
  const aberto = periodo ? periodo.aberto : true;
  const agoraServidor = periodo ? new Date(periodo.agora) : new Date();
  const hoje = hojeSP(agoraServidor);

  const edital = publicacoes.find((p) => p.categoria === "edital" && p.tem_arquivo);
  const documentos = publicacoes.filter((p) => p.categoria !== "comunicado");
  const comunicados = publicacoes.filter((p) => p.categoria === "comunicado");
  const etapas = cronograma.map((c) => ({ ...c, situacao: situacaoEtapa(c, hoje) }));
  const atuais = etapas.filter((c) => c.situacao === "andamento");
  const proxima = etapas.find((c) => c.situacao === "futura");
  const niveis = (["junior", "pleno", "senior"] as const).filter((n) => vagas.some((v) => v.nivel === n));
  const totalVagas = vagas.reduce((s, v) => s + v.quantidade, 0);
  const salarios = vagas.map((v) => Number(v.remuneracao));

  return (
    <>
      <Cabecalho periodo={situacao} email={logado ? String(claims?.claims?.email ?? "") : null} linkPainel={souComissao} />

      {/* 1. Destaque: o que é, situação das inscrições e as duas ações principais */}
      <section className="portal-hero" aria-labelledby="t-processo">
        <div className="wrap portal-hero-grid">
          <div className="portal-hero-texto">
            <p className="portal-hero-edital">Edital nº 001/2026 · Companhia de Urbanização de Goiânia</p>
            <h1 id="t-processo">Processo Seletivo Simplificado 2026</h1>
            <p>
              Contratação temporária de analistas para os Grupos A, B e C, nos níveis Júnior, Pleno e Sênior. Seleção por análise curricular e
              entrevista técnica. Inscrição somente pela internet, nesta plataforma.
            </p>
          </div>

          <div className="portal-status" aria-live="polite">
            <span className={`portal-status-selo is-${estado}`}>
              {estado === "aberto" ? "Inscrições abertas" : estado === "antes" ? "Inscrições em breve" : "Inscrições encerradas"}
            </span>
            <p className="portal-status-periodo">{situacao.replace("Inscrições: ", "")}</p>
            {detalheEstado ? <p className="portal-status-detalhe">{detalheEstado}</p> : null}
            <div className="portal-status-acoes">
              {estado === "antes" ? (
                // Antes da abertura não há o que preencher: o botão fica desativado e diz quando abre.
                <button type="button" className="btn btn-primary btn-grande" disabled>
                  Inscrições abrem em {aberturaTexto}
                </button>
              ) : (
                <Link href={logado ? "/inscricao" : "/entrar"} className="btn btn-primary btn-grande" aria-disabled={!aberto}>
                  {logado ? "Continuar minha inscrição" : "Iniciar minha inscrição"}
                </Link>
              )}
              {edital ? (
                <a className="btn btn-grande" href={`/publicacoes/${edital.id}`} target="_blank" rel="noopener noreferrer">
                  Baixar o edital (PDF)
                </a>
              ) : (
                <a className="btn btn-grande" href="#documentos">
                  Edital e documentos
                </a>
              )}
            </div>
            <p className="portal-status-nota">Taxa de inscrição: R$ 100,00, por Pix (item 4.8).</p>
          </div>
        </div>
      </section>

      <main className="wrap portal-main">
        {/* 2. Números principais */}
        {vagas.length ? (
          <ul className="portal-numeros" aria-label="Resumo do processo">
            <li>
              <b>{totalVagas}</b>
              <span>vagas imediatas</span>
            </li>
            <li>
              <b>3 grupos</b>
              <span>Júnior, Pleno e Sênior</span>
            </li>
            <li>
              <b>
                {moeda(Math.min(...salarios))} a {moeda(Math.max(...salarios))}
              </b>
              <span>remuneração bruta mensal</span>
            </li>
            <li>
              <b>2 etapas</b>
              <span>análise curricular e entrevista</span>
            </li>
          </ul>
        ) : null}

        <div className="portal-colunas">
          {/* 3. Coluna principal: comunicados e documentos oficiais */}
          <div className="portal-coluna-principal">
            <section className="portal-bloco" id="comunicados" aria-labelledby="t-comunicados">
              <header className="portal-bloco-topo">
                <h2 id="t-comunicados">Comunicados</h2>
              </header>
              {comunicados.length === 0 ? (
                <p className="portal-vazio">Nenhum comunicado até o momento.</p>
              ) : (
                <ul className="portal-lista">
                  {comunicados.map((c) => (
                    <li key={c.id}>
                      <div className="portal-lista-data">
                        <span>{fmt.format(new Date(c.publicado_em))}</span>
                        {ehNovo(c.publicado_em, agoraServidor) ? <span className="pill pill-ok">Novo</span> : null}
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
                  ))}
                </ul>
              )}
              <p className="portal-rodape-bloco">
                Retificações, resultados, convocações e demais atos são publicados exclusivamente nesta plataforma. Acompanhar as publicações é
                responsabilidade do candidato (itens 13.2 e 13.4 do edital).
              </p>
            </section>

            <section className="portal-bloco" id="documentos" aria-labelledby="t-documentos">
              <header className="portal-bloco-topo">
                <h2 id="t-documentos">Edital e documentos oficiais</h2>
              </header>
              {documentos.length === 0 ? (
                <p className="portal-vazio">Os documentos oficiais serão publicados aqui.</p>
              ) : (
                <ul className="portal-docs">
                  {documentos.map((d) => (
                    <li key={d.id}>
                      <span className="portal-docs-icone" aria-hidden>
                        PDF
                      </span>
                      <div className="portal-docs-info">
                        <span className="portal-docs-cat">
                          {CATEGORIAS[d.categoria]}
                          {ehNovo(d.publicado_em, agoraServidor) ? <span className="pill pill-ok">Novo</span> : null}
                        </span>
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
                  ))}
                </ul>
              )}
            </section>
          </div>

          {/* 4. Lateral: como se inscrever e contato */}
          <aside className="portal-coluna-lateral">
            <section className="portal-bloco" aria-labelledby="t-como">
              <header className="portal-bloco-topo">
                <h2 id="t-como">Como se inscrever</h2>
              </header>
              <ol className="portal-passos">
                <li>
                  <b>Acesse com seu e-mail</b>
                  <span>Você recebe um código de acesso, sem criar senha.</span>
                </li>
                <li>
                  <b>Preencha e anexe</b>
                  <span>Dados pessoais, vaga, formação, experiência, documentos e comprovante do Pix. Tudo é salvo e você pode continuar depois.</span>
                </li>
                <li>
                  <b>Confira e envie</b>
                  <span>Revise e clique em Enviar solicitação. Depois do envio, a inscrição não pode ser alterada.</span>
                </li>
              </ol>
            </section>

            <section className="portal-bloco" id="contato" aria-labelledby="t-contato">
              <header className="portal-bloco-topo">
                <h2 id="t-contato">Dúvidas e recursos</h2>
              </header>
              <p>Somente pelo e-mail oficial da Comissão Organizadora:</p>
              <a className="portal-email" href={`mailto:${EMAIL_OFICIAL}`}>
                {EMAIL_OFICIAL}
              </a>
              <ul className="portal-notas">
                <li>Dúvidas respondidas em até 48 horas úteis (item 4.12).</li>
                <li>Recursos com o formulário do Anexo VI, em até 3 dias úteis após a publicação do resultado (item 9.2).</li>
                <li>Pedido de isenção da taxa só no portal, durante a inscrição (item 4.10).</li>
              </ul>
            </section>
          </aside>
        </div>

        {/* 5. Vagas e remuneração */}
        {vagas.length ? (
          <section className="portal-bloco" id="vagas" aria-labelledby="t-vagas">
            <header className="portal-bloco-topo">
              <h2 id="t-vagas">Vagas e remuneração</h2>
              <span className="portal-bloco-ref">Remuneração bruta mensal · item 2.1 do edital</span>
            </header>
            <div className="tabela-wrap">
              <table className="tabela tabela-estatica portal-tabela-vagas">
                <thead>
                  <tr>
                    <th>Nível</th>
                    {(["A", "B", "C"] as const).map((g) => (
                      <th key={g}>
                        <span className="portal-so-largo">Grupo </span>
                        {g}
                        <small>{GRUPOS[g].descricao}</small>
                      </th>
                    ))}
                    <th>Remuneração</th>
                  </tr>
                </thead>
                <tbody>
                  {niveis.map((n) => (
                    <tr key={n}>
                      <td>
                        <b>{NIVEIS[n].nome}</b>
                      </td>
                      {(["A", "B", "C"] as const).map((g) => (
                        <td key={g}>{vagas.find((v) => v.nivel === n && v.grupo === g)?.quantidade ?? "—"}</td>
                      ))}
                      <td>
                        {moeda(Number(vagas.find((v) => v.nivel === n)?.remuneracao ?? 0))}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        ) : null}

        {/* 6. Cronograma (recolhível) */}
        {etapas.length ? (
          <section className="portal-bloco" id="cronograma" aria-labelledby="t-cronograma">
            <details className="portal-recolher" open>
              <summary>
                <span className="recolher-triangulo" aria-hidden />
                <h2 id="t-cronograma">Cronograma</h2>
                <span className="portal-recolher-resumo">
                  {atuais.length
                    ? `Agora: ${atuais.map((a) => a.evento).join(" · ")}`
                    : proxima
                      ? `Próxima etapa: ${proxima.evento} (${textoData(proxima)})`
                      : "Processo concluído"}
                </span>
              </summary>
              <ol className="crono">
                {etapas.map((c) => (
                  <li key={c.ordem} className={`crono-item is-${c.situacao}`}>
                    <span className="crono-marca" aria-hidden>
                      {c.situacao === "concluida" ? "✓" : c.ordem}
                    </span>
                    <span className="crono-evento">
                      {c.evento}
                      {c.situacao === "andamento" ? <span className="pill pill-ok">Em andamento</span> : null}
                      {c.situacao === "concluida" ? <span className="sr-only"> (concluída)</span> : null}
                    </span>
                    <span className="crono-data">{textoData(c)}</span>
                  </li>
                ))}
              </ol>
            </details>
          </section>
        ) : null}
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
