import { RecursosLista } from "./RecursosLista";

export const metadata = { title: "Recursos · Painel da Comissão", robots: { index: false, follow: false } };

export default function RecursosPage() {
  return (
    <div className="card">
      <header className="step-head">
        <p className="eyebrow">Inscrições</p>
        <h2>Recursos</h2>
        <p className="lead">
          Os recursos chegam exclusivamente por e-mail (item 9.2 do edital), não pela plataforma. Registre aqui o que foi recebido e a decisão, sempre
          fundamentada (itens 1.5 e 1.6). Cabem recursos contra: indeferimento de isenção, indeferimento de inscrição, resultado preliminar de habilitação e
          AC, resultado preliminar da entrevista, resultado de reservas de vagas e resultado preliminar final (item 9.1). Quando o recurso é contra o
          indeferimento da <b>inscrição</b> e é deferido, ela volta a homologada automaticamente (item 4.13, minuta v11).
        </p>
      </header>
      <RecursosLista />
    </div>
  );
}
