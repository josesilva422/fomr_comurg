import type { ReactNode } from "react";

/** Rótulo + controle + dica + mensagem de erro, no padrão visual do formulário. */
export function Campo({
  id,
  rotulo,
  obrigatorio,
  erro,
  dica,
  className = "",
  children,
}: {
  id: string;
  rotulo: string;
  obrigatorio?: boolean;
  erro?: string;
  dica?: string;
  className?: string;
  children: ReactNode;
}) {
  return (
    <div className={`field ${className}${erro ? " invalid" : ""}`}>
      <label htmlFor={id}>
        {rotulo}
        {obrigatorio ? (
          <>
            {" "}
            <b className="req" aria-hidden="true">
              *
            </b>
          </>
        ) : null}
      </label>
      {children}
      {dica ? <p className="hint">{dica}</p> : null}
      {erro ? (
        <p className="err" role="alert">
          {erro}
        </p>
      ) : null}
    </div>
  );
}
