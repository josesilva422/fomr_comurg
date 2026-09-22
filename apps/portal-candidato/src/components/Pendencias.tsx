import type { Pendencia } from "@/lib/tipos-inscricao";

/**
 * Lista o que ainda falta (mensagens vindas do banco: publico.verificar_inscricao).
 * Separa automaticamente o que bloqueia o envio (`bloqueia: true`) do que é só um aviso
 * (ex.: título/curso sem documento anexado — pode enviar, mas o item não pontua).
 */
export function Pendencias({ itens, titulo = "Para continuar, falta:" }: { itens: Pendencia[]; titulo?: string }) {
  if (!itens.length) return null;
  const bloqueantes = itens.filter((p) => p.bloqueia);
  const avisos = itens.filter((p) => !p.bloqueia);
  return (
    <>
      {bloqueantes.length ? (
        <div className="alert alert-err" role="alert">
          <div>
            <p>
              <b>{titulo}</b>
            </p>
            <ul style={{ margin: "6px 0 0 18px" }}>
              {bloqueantes.map((p, i) => (
                <li key={`${p.codigo}-${i}`}>{p.mensagem}</li>
              ))}
            </ul>
          </div>
        </div>
      ) : null}
      {avisos.length ? (
        <div className="alert alert-warn" role="status">
          <div>
            <p>
              <b>Fique atento:</b>
            </p>
            <ul style={{ margin: "6px 0 0 18px" }}>
              {avisos.map((p, i) => (
                <li key={`${p.codigo}-${i}`}>{p.mensagem}</li>
              ))}
            </ul>
          </div>
        </div>
      ) : null}
    </>
  );
}
