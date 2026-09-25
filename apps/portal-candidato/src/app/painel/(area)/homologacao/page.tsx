import { HomologacaoLista } from "./HomologacaoLista";

export const metadata = { title: "Homologação · Painel da Comissão", robots: { index: false, follow: false } };

export default function HomologacaoPage() {
  return (
    <div className="card">
      <header className="step-head">
        <p className="eyebrow">Inscrições · Homologação</p>
        <h2>Homologação das inscrições</h2>
        <p className="lead">
          Aprove ou rejeite cada inscrição enviada (Anexo IV, item 10: até 20/10/2026). Para rejeitar, é obrigatório explicar o motivo, que o candidato vê
          e contra o qual pode recorrer (item 9.1, alínea b). Aparecem aqui as inscrições pagas por Pix, com isenção deferida ou com pagamento confirmado
          após a isenção indeferida. Inscrição rejeitada deixa de entrar na análise curricular e na convocação.
        </p>
      </header>
      <HomologacaoLista />
    </div>
  );
}
