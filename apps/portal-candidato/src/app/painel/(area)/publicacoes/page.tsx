import { PublicacoesGestao } from "./PublicacoesGestao";
import { CronogramaEditor } from "./CronogramaEditor";

export const metadata = { title: "Publicações · Painel da Comissão", robots: { index: false, follow: false } };

export default function PublicacoesPage() {
  return (
    <div style={{ display: "grid", gap: 20 }}>
      <div className="card">
        <header className="step-head">
          <p className="eyebrow">Portal · Página inicial</p>
          <h2>Publicações</h2>
          <p className="lead">
            Edital, retificações, anexos, resultados e comunicados que aparecem na página inicial do portal, sem login. Pelo item 13.2 do edital, os
            atos do certame (exceto o edital, também no Diário Oficial) são publicados exclusivamente nesta plataforma. Nada é apagado: retirar do ar
            só oculta, e tudo fica na auditoria.
          </p>
        </header>
        <PublicacoesGestao />
      </div>
      <div className="card">
        <header className="step-head">
          <p className="eyebrow">Anexo IV do edital</p>
          <h2>Cronograma</h2>
          <p className="lead">
            O cronograma da página inicial vem daqui. Altere só quando houver retificação publicada; a justificativa é obrigatória e fica na auditoria.
          </p>
        </header>
        <CronogramaEditor />
      </div>
    </div>
  );
}
