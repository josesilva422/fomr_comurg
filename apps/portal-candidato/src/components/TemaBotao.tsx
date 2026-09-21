"use client";

// Alterna entre tema claro e escuro. Sem escolha, o site segue o tema do sistema.
// O rótulo troca por CSS (ver globals.css), então não há estado nem divergência na hidratação.
export function TemaBotao() {
  function alternar() {
    const atual = document.documentElement.getAttribute("data-theme");
    const escuroAgora = atual ? atual === "dark" : window.matchMedia("(prefers-color-scheme: dark)").matches;
    const proximo = escuroAgora ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", proximo);
    try {
      localStorage.setItem("pss-tema", proximo);
    } catch {
      /* sem armazenamento: vale só nesta visita */
    }
  }

  return (
    <button type="button" className="theme-btn" onClick={alternar}>
      <span className="t-escuro">Tema escuro</span>
      <span className="t-claro">Tema claro</span>
    </button>
  );
}
