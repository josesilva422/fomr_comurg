import type { Pendencia } from "@/lib/tipos-inscricao";

/** Lista o que ainda falta (mensagens vindas do banco: publico.verificar_inscricao). */
export function Pendencias({ itens, titulo = "Para continuar, falta:" }: { itens: Pendencia[]; titulo?: string }) {
  if (!itens.length) return null;
  return (
    <div className="alert alert-err" role="alert">
      <div>
        <p>
          <b>{titulo}</b>
        </p>
        <ul style={{ margin: "6px 0 0 18px" }}>
          {itens.map((p, i) => (
            <li key={`${p.codigo}-${i}`}>{p.mensagem}</li>
          ))}
        </ul>
      </div>
    </div>
  );
}
