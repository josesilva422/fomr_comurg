import { EliminacoesLista } from "./EliminacoesLista";

export const metadata = { title: "Eliminação por fraude · Painel da Comissão", robots: { index: false, follow: false } };

export default function EliminacoesPage() {
  return (
    <div className="card">
      <header className="step-head">
        <p className="eyebrow">Inscrições</p>
        <h2>Eliminação por fraude ou falsidade</h2>
        <p className="lead">
          Falsidade documental em qualquer fase leva à eliminação imediata e à comunicação às autoridades (itens 5.5.4 e 14.3 do edital). A decisão é
          <b> exclusivamente humana</b> — a extração por IA só sinaliza indícios (documento ilegível, instituição ausente no e-MEC, suspeita de adulteração
          etc.), nunca decide. Use com extremo cuidado: a justificativa precisa citar o indício constatado.
        </p>
      </header>
      <EliminacoesLista />
    </div>
  );
}
