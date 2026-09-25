import { ClassificacaoTabela } from "./ClassificacaoTabela";

export const metadata = { title: "Entrevista técnica · Painel da Comissão", robots: { index: false, follow: false } };

export default function ClassificacaoPage() {
  return (
    <div className="card">
      <header className="step-head">
        <p className="eyebrow">Classificação final · Entrevista técnica</p>
        <h2>Entrevista técnica — visão geral</h2>
        <p className="lead">
          PF = AC (máx. 60) + ET (máx. 40), por Grupo e Nível, só com os convocados para a entrevista. A ET é a média das fichas dos avaliadores e só
          aparece quando o candidato tem pelo menos 3 fichas; a nota de cada avaliador não aparece aqui. Cada avaliador envia a sua em &quot;Minhas
          fichas&quot;. Nada aqui é publicado ao candidato.
        </p>
      </header>
      <ClassificacaoTabela />
    </div>
  );
}
