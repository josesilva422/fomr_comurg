import Link from "next/link";
import { Cabecalho } from "@/components/Cabecalho";
import { createClient } from "@/lib/supabase/server";

const fmt = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "America/Sao_Paulo" });

type Periodo = { abertura: string; encerramento: string; agora: string; aberto: boolean } | null;

export default async function Inicio() {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const logado = Boolean(claims?.claims);
  // Conferido sempre no servidor: quem não é da Comissão nunca recebe esse HTML no navegador.
  const souComissao = logado ? (await supabase.schema("painel").rpc("sou_da_comissao")).data === true : false;
  const { data } = await supabase.rpc("periodo_inscricoes");
  const periodo: Periodo = Array.isArray(data) && data.length ? data[0] : null;

  let situacao = "Inscrições: 28/09 a 13/10/2026";
  let mensagem = "";
  if (periodo) {
    const ab = new Date(periodo.abertura);
    const enc = new Date(periodo.encerramento);
    situacao = `Inscrições: ${fmt.format(ab)} a ${fmt.format(enc)}`;
    const agora = new Date(periodo.agora).getTime(); // horário do servidor (banco)
    if (agora < ab.getTime()) mensagem = `As inscrições abrem em ${fmt.format(ab)}.`;
    else if (agora > enc.getTime()) mensagem = "O período de inscrições foi encerrado.";
  }
  const aberto = periodo ? periodo.aberto : true;

  return (
    <>
      <Cabecalho periodo={situacao} email={logado ? String(claims?.claims?.email ?? "") : null} linkPainel={souComissao} />
      <main className="wrap" style={{ padding: "24px 16px 64px" }}>
        <section className="card hero">
          <p className="eyebrow">Edital 2026 · Analista de Governança</p>
          <h1>Processo Seletivo Simplificado da COMURG</h1>
          <p className="lead">
            Faça sua inscrição pela internet, anexe os documentos e envie sua solicitação. Depois do envio, a inscrição é
            definitiva e só a Comissão Organizadora tem acesso às informações.
          </p>

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
          </div>
        </section>
      </main>
    </>
  );
}
