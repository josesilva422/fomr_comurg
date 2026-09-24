import { UsuariosLista } from "./UsuariosLista";
import { ConvitesSecao } from "./ConvitesSecao";

export const metadata = { title: "Usuários do painel · Painel da Comissão", robots: { index: false, follow: false } };

export default function UsuariosPage() {
  return (
    <div className="card">
      <header className="step-head">
        <p className="eyebrow">Acesso · Usuários do painel</p>
        <h2>Quem tem acesso ao painel</h2>
        <p className="lead">
          Todos os usuários abaixo pertencem à Comissão e só entram com senha e código enviado por e-mail. Aqui você vê a situação de cada conta, o último acesso
          e os candidatos cujas fichas de entrevista técnica foram lançadas por cada avaliador. Novos usuários entram por convite (abaixo); a desativação é feita direto no banco.
        </p>
      </header>
      <UsuariosLista />
      <ConvitesSecao />
    </div>
  );
}
