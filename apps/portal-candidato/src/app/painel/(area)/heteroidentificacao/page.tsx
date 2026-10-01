import { HeteroidentificacaoLista } from "./HeteroidentificacaoLista";

export const metadata = { title: "Heteroidentificação · Painel da Comissão", robots: { index: false, follow: false } };

export default function HeteroidentificacaoPage() {
  return (
    <div className="card">
      <header className="step-head">
        <p className="eyebrow">Classificação final</p>
        <h2>Heteroidentificação</h2>
        <p className="lead">
          Candidatos autodeclarados negros, convocados para a entrevista técnica, passam por heteroidentificação na data da respectiva entrevista (Anexo IV,
          item 19). A comissão específica (mínimo de 5 membros, diversidade de gênero e cor, presencial ou por videoconferência gravada) decide de forma
          sempre motivada; cabe recurso a uma comissão recursal de composição distinta (item 10.4).
        </p>
      </header>
      <HeteroidentificacaoLista />
    </div>
  );
}
