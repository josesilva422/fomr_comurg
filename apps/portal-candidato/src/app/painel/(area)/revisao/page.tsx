import { FilaRevisaoLista } from "./FilaRevisaoLista";

export const metadata = { title: "Fila de revisão · Painel da Comissão", robots: { index: false, follow: false } };

export default function RevisaoPage() {
  return (
    <div className="card">
      <header className="step-head">
        <p className="eyebrow">Pré-análise</p>
        <h2>Fila de revisão da Comissão</h2>
        <p className="lead">
          Um documento por linha, com o que a IA extraiu ao lado. A IA só lê e aponta divergências — nunca decide; marcar como revisada (confere) ou
          corrigida (a IA leu errado) é apenas o registro de que um humano confrontou o documento, não uma decisão de habilitação ou pontuação. Documentos
          ainda não extraídos aparecem na fila; use &quot;Extrair com IA&quot; na página do candidato para gerar a primeira leitura.
        </p>
      </header>
      <FilaRevisaoLista />
    </div>
  );
}
