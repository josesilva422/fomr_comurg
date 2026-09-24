import { ClassificacaoTabela } from "./ClassificacaoTabela";

export const metadata = { title: "Entrevista técnica · Painel da Comissão", robots: { index: false, follow: false } };

export default function ClassificacaoPage() {
  return (
    <div className="card">
      <header className="step-head">
        <p className="eyebrow">Classificação final · Entrevista técnica</p>
        <h2>Classificação — análise curricular + entrevista</h2>
        <p className="lead">
          PF = AC (máx. 60) + ET (máx. 40), por Grupo e Nível, só com os convocados para a entrevista. Clique num candidato e abra a aba &quot;Entrevista
          técnica&quot; para lançar as fichas dos avaliadores. Nada aqui é publicado ao candidato.
        </p>
      </header>
      <ClassificacaoTabela />
    </div>
  );
}
