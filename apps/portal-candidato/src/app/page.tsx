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
const moeda = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
const EMAIL_OFICIAL = "pss2026comurg@comurg.com.br";

type Periodo = { abertura: string; encerramento: string; agora: string; aberto: boolean } | null;

// Página inicial pública: site oficial do processo (edital, item 13.2) — inscrição, documentos, comunicados,
// cronograma (Anexo IV) e vagas (item 2.1). Publicações e cronograma vêm do banco (a Comissão publica pelo painel).
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
  let mensagem = "";
  let estado: "antes" | "aberto" | "encerrado" = "aberto";
  if (periodo) {
    const ab = new Date(periodo.abertura);
    const enc = new Date(periodo.encerramento);
    situacao = `Inscrições: ${fmt.format(ab)} a ${fmt.format(enc)}`;
    const agora = new Date(periodo.agora).getTime(); // horário do servidor (banco)
    if (agora < ab.getTime()) {
      estado = "antes";
      mensagem = `As inscrições abrem em ${fmt.format(ab)}.`;
    } else if (agora > enc.getTime()) {
      estado = "encerrado";
      mensagem = "O período de inscrições foi encerrado.";
    }
  }
  const aberto = periodo ? periodo.aberto : true;
  const agoraServidor = periodo ? new Date(periodo.agora) : new Date();
  const hoje = hojeSP(agoraServidor);

  const documentos = publicacoes.filter((p) => p.categoria !== "comunicado");
  const comunicados = publicacoes.filter((p) => p.categoria === "comunicado");
  const etapas = cronograma.map((c) => ({ ...c, situacao: situacaoEtapa(c, hoje) }));
  const proxima = etapas.find((c) => c.situacao === "andamento") ?? etapas.find((c) => c.situacao === "futura");
  const niveis = (["junior", "pleno", "senior"] as const).filter((n) => vagas.some((v) => v.nivel === n));
  const totalVagas = vagas.reduce((s, v) => s + v.quantidade, 0);

  return (
    <>
      <Cabecalho periodo={situacao} email={logado ? String(claims?.claims?.email ?? "") : null} linkPainel={souComissao} />
      <main className="wrap" style={{ padding: "24px 16px 64px" }}>
        <section className="card hero">
          <p className="eyebrow">Edital nº 001/2026</p>
          <h1>Processo Seletivo Simplificado da COMURG</h1>
          <p className="lead">
            Faça sua inscrição pela internet, anexe os documentos e envie sua solicitação. Depois do envio, a inscrição é
            definitiva e só a Comissão Organizadora tem acesso às informações.
          </p>

          <div className="home-status">
            <span className={`pill ${estado === "aberto" ? "pill-ok" : estado === "antes" ? "pill-info" : "pill-muted"}`}>
              {estado === "aberto" ? "Inscrições abertas" : estado === "antes" ? "Inscrições em breve" : "Inscrições encerradas"}
            </span>
            <span>{situacao.replace("Inscrições: ", "Período: ")}</span>
            {proxima ? (
              <span className="hint">
                {proxima.situacao === "andamento" ? "Agora: " : "Próxima etapa: "}
                <b>{proxima.evento}</b> ({textoData(proxima)})
              </span>
            ) : null}
          </div>

          {mensagem ? (
            <div className="alert alert-info">
              <p>{mensagem}</p>
            </div>
          ) : null}

          <ol className="passos-home">
            <li>
              <b>1. Acesse com seu e-mail</b>
              Você recebe um código, sem criar senha.
            </li>
            <li>
              <b>2. Preencha e anexe</b>
              Dados pessoais, formação, experiência, documentos e comprovante do Pix. Pode salvar e continuar depois.
            </li>
            <li>
              <b>3. Confira e envie</b>
              Revise tudo e clique em <em>Enviar solicitação</em>.
            </li>
          </ol>

          <div className="acoes-form" style={{ justifyContent: "flex-start", marginTop: 28 }}>
            <Link href={logado ? "/inscricao" : "/entrar"} className="btn btn-primary" aria-disabled={!aberto}>
              {logado ? "Continuar minha inscrição" : "Iniciar minha inscrição"}
            </Link>
            <a href="#documentos" className="btn">
              Edital e documentos
            </a>
            <a href="#cronograma" className="btn btn-ghost">
              Cronograma
            </a>
          </div>
        </section>

        <div className="home-grid">
          <section className="card" id="documentos" aria-labelledby="t-documentos">
            <p className="eyebrow">Documentos oficiais</p>
            <h2 id="t-documentos">Edital, retificações e resultados</h2>
            {documentos.length === 0 ? (
              <div className="empty">Os documentos oficiais serão publicados aqui.</div>
            ) : (
              <ul className="doc-lista">
                {documentos.map((d) => (
                  <li key={d.id}>
                    <div className="doc-info">
                      <span className="doc-cat">
                        {CATEGORIAS[d.categoria]}
                        {ehNovo(d.publicado_em, agoraServidor) ? <span className="pill pill-ok">Novo</span> : null}
                      </span>
                      <b>{d.titulo}</b>
                      {d.texto ? <span className="doc-texto">{d.texto}</span> : null}
                      <small className="hint">
                        Publicado em {fmt.format(new Date(d.publicado_em))}
                        {d.arquivo_bytes ? ` · PDF, ${tamanhoArquivo(d.arquivo_bytes)}` : ""}
                      </small>
                    </div>
                    {d.tem_arquivo ? (
                      <a className="btn btn-sm" href={`/publicacoes/${d.id}`} target="_blank" rel="noopener noreferrer">
                        Abrir PDF
                      </a>
                    ) : null}
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="card" id="comunicados" aria-labelledby="t-comunicados">
            <p className="eyebrow">Comunicados</p>
            <h2 id="t-comunicados">Avisos e atualizações</h2>
            {comunicados.length === 0 ? (
              <div className="empty">Nenhum comunicado até o momento.</div>
            ) : (
              <ul className="doc-lista">
                {comunicados.map((c) => (
                  <li key={c.id}>
                    <div className="doc-info">
                      <span className="doc-cat">
                        {fmt.format(new Date(c.publicado_em))}
                        {ehNovo(c.publicado_em, agoraServidor) ? <span className="pill pill-ok">Novo</span> : null}
                      </span>
                      <b>{c.titulo}</b>
                      {c.texto ? <span className="doc-texto">{c.texto}</span> : null}
                    </div>
                    {c.tem_arquivo ? (
                      <a className="btn btn-sm" href={`/publicacoes/${c.id}`} target="_blank" rel="noopener noreferrer">
                        Abrir PDF
                      </a>
                    ) : null}
                  </li>
                ))}
              </ul>
            )}
            <p className="hint" style={{ marginTop: 14 }}>
              Retificações, resultados, convocações e demais atos do processo são publicados exclusivamente nesta plataforma. Acompanhar as publicações é
              responsabilidade do candidato (itens 13.2 e 13.4 do edital).
            </p>
          </section>
        </div>

        {etapas.length ? (
          <section className="card" id="cronograma" aria-labelledby="t-cronograma" style={{ marginTop: 20 }}>
            <p className="eyebrow">Anexo IV do edital</p>
            <h2 id="t-cronograma">Cronograma</h2>
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
          </section>
        ) : null}

        <div className="home-grid" style={{ marginTop: 20 }}>
          {vagas.length ? (
            <section className="card" id="vagas" aria-labelledby="t-vagas">
              <p className="eyebrow">Item 2.1 do edital</p>
              <h2 id="t-vagas">Vagas e remuneração</h2>
              <div className="tabela-wrap">
                <table className="tabela tabela-estatica">
                  <thead>
                    <tr>
                      <th>Nível</th>
                      {(["A", "B", "C"] as const).map((g) => (
                        <th key={g} style={{ textAlign: "center" }}>
                          {GRUPOS[g].nome}
                        </th>
                      ))}
                      <th style={{ textAlign: "right" }}>Remuneração</th>
                    </tr>
                  </thead>
                  <tbody>
                    {niveis.map((n) => (
                      <tr key={n}>
                        <td>
                          <b>{NIVEIS[n].nome}</b>
                        </td>
                        {(["A", "B", "C"] as const).map((g) => (
                          <td key={g} style={{ textAlign: "center" }}>
                            {vagas.find((v) => v.nivel === n && v.grupo === g)?.quantidade ?? "—"}
                          </td>
                        ))}
                        <td style={{ textAlign: "right" }}>{moeda.format(Number(vagas.find((v) => v.nivel === n)?.remuneracao ?? 0))}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <p className="hint" style={{ marginTop: 10 }}>
                {totalVagas} vagas imediatas. {(["A", "B", "C"] as const).map((g) => `${GRUPOS[g].nome}: ${GRUPOS[g].descricao}`).join(" · ")}.
              </p>
            </section>
          ) : null}

          <section className="card" id="contato" aria-labelledby="t-contato">
            <p className="eyebrow">Fale com a Comissão</p>
            <h2 id="t-contato">Dúvidas e recursos</h2>
            <p>
              Dúvidas e recursos são enviados <b>exclusivamente</b> para o e-mail oficial{" "}
              <a href={`mailto:${EMAIL_OFICIAL}`}>
                <b>{EMAIL_OFICIAL}</b>
              </a>
              . As respostas às dúvidas são dadas em até 48 horas úteis (item 4.12).
            </p>
            <p className="hint">
              Recursos: formulário do Anexo VI preenchido e assinado, em até 3 dias úteis após a publicação do resultado (item 9.2). Pedidos de isenção
              da taxa são feitos só aqui no portal, durante a inscrição (item 4.10). Mensagens enviadas por outros canais não são consideradas.
            </p>
          </section>
        </div>
      </main>
    </>
  );
}
