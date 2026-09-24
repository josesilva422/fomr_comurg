import { RelatorioRespostas } from "../RelatorioRespostas";

export const metadata = { title: "Relatórios · Painel da Comissão", robots: { index: false, follow: false } };

export default function RelatoriosPage() {
  return (
    <div className="card">
      <header className="step-head">
        <p className="eyebrow">Relatórios</p>
        <h2>Respostas do formulário</h2>
        <p className="lead">
          Baixe as respostas dos candidatos para conferir informações. Para um candidato só, abra a página dele e use &quot;Baixar formulário (PDF)&quot;.
        </p>
      </header>
      <RelatorioRespostas />
    </div>
  );
}
