import type { EstadoAutoSalvar } from "@/lib/auto-salvar";

// Linha de estado do salvamento automático de um cartão do formulário.
export function StatusAutoSalvar({ estado, faltando, erro }: { estado: EstadoAutoSalvar; faltando: string[]; erro?: string }) {
  if (estado === "erro") {
    return (
      <div className="alert alert-err" role="alert" style={{ marginTop: 12 }}>
        <p>{erro || "Não foi possível salvar. Confira os dados."}</p>
      </div>
    );
  }
  const texto =
    estado === "salvando" || estado === "pendente"
      ? "Salvando…"
      : estado === "salvo"
        ? "✓ Salvo automaticamente"
        : `Para salvar, falta: ${faltando.join(" ")}`;
  return (
    <p className="hint" aria-live="polite" style={{ marginTop: 12, color: estado === "salvo" ? "var(--ok-text)" : undefined }}>
      {texto}
    </p>
  );
}
