import { MinhasFichas } from "./MinhasFichas";

export const metadata = { title: "Minhas fichas · Painel da Comissão", robots: { index: false, follow: false } };

export default function MinhasFichasPage() {
  return (
    <div className="card">
      <header className="step-head">
        <p className="eyebrow">Entrevista técnica · Avaliador</p>
        <h2>Minhas fichas</h2>
        <p className="lead">
          Candidatos convocados para a entrevista e a sua ficha em cada um. Você vê e corrige só as suas notas; os outros avaliadores não as veem, e
          você não vê as deles. A média aparece na visão geral quando o candidato tiver pelo menos 3 fichas.
        </p>
      </header>
      <MinhasFichas />
    </div>
  );
}
