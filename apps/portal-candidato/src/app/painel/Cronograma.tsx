import type { CronogramaItem } from "@/lib/pontuacao";

const fmt = (iso: string | null) => (iso ? new Date(iso + "T12:00:00").toLocaleDateString("pt-BR") : null);

function periodo(item: CronogramaItem) {
  if (item.detalhe) return item.detalhe;
  const ini = fmt(item.data_inicio);
  const fim = fmt(item.data_fim);
  if (ini && fim) return ini === fim ? ini : `${ini} a ${fim}`;
  if (fim) return `Até ${fim}`;
  if (ini) return `A partir de ${ini}`;
  return "—";
}

// Itens que o edital atualizado em 22/09/2026 antecipou (Anexo IV) — só para destacar no painel.
const ITENS_ANTECIPADOS = new Set([12, 13, 14, 15, 16, 17, 18]);

export function Cronograma({ itens }: { itens: CronogramaItem[] }) {
  if (!itens.length) return null;
  return (
    <details className="card" style={{ marginBottom: 16 }}>
      <summary style={{ cursor: "pointer", fontWeight: 700 }}>Cronograma do certame (Anexo IV)</summary>
      <div className="tabela-wrap" style={{ marginTop: 12 }}>
        <table className="tabela">
          <thead>
            <tr>
              <th>Nº</th>
              <th>Evento</th>
              <th>Prazo / Data</th>
            </tr>
          </thead>
          <tbody>
            {itens.map((item) => (
              <tr key={item.ordem}>
                <td>{item.ordem}</td>
                <td>{item.evento}</td>
                <td>
                  {periodo(item)}
                  {ITENS_ANTECIPADOS.has(item.ordem) ? (
                    <span className="hint" style={{ marginLeft: 8 }}>
                      (antecipado no edital de 22/09/2026)
                    </span>
                  ) : null}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </details>
  );
}
