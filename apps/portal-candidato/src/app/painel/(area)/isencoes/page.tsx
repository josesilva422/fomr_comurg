import { IsencoesLista } from "./IsencoesLista";

export const metadata = { title: "Isenções · Painel da Comissão", robots: { index: false, follow: false } };

export default function IsencoesPage() {
  return (
    <div className="card">
      <header className="step-head">
        <p className="eyebrow">Inscrições · Isenção da taxa</p>
        <h2>Pedidos de isenção da taxa de inscrição</h2>
        <p className="lead">
          Confira os documentos de cada pedido e registre a decisão com o motivo (itens 4.10 e 4.10.1 do edital; decreto municipal, art. 4º). Pedido com dados
          incompletos ou incorretos é indeferido (art. 4º, §5º). O resultado dos pedidos deve sair até 08/10/2026 (Anexo IV). A decisão é sempre da Comissão:
          o sistema apenas guarda o que for decidido, com autor, data e motivo.
        </p>
      </header>
      <IsencoesLista />
    </div>
  );
}
