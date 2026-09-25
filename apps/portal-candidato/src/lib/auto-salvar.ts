"use client";

import { useCallback, useEffect, useRef, useState } from "react";

// Salvamento automático dos cartões do formulário (títulos, cursos e vínculos), sem botão "Salvar": assim que o
// cartão tem os campos obrigatórios preenchidos, ele é gravado depois de uma pequena pausa na digitação; cada
// alteração seguinte grava de novo. Pedido do responsável em 25/09/2026.

export type EstadoAutoSalvar = "incompleto" | "pendente" | "salvando" | "salvo" | "erro";

/** Salvamentos ainda não feitos de todos os cartões montados (para "Continuar" esperar por eles). */
const pendentes = new Set<() => Promise<void>>();

/** Grava na hora tudo o que está pendente nos cartões da tela e espera terminar. */
export async function salvarPendentes(): Promise<void> {
  await Promise.all([...pendentes].map((f) => f()));
}

export function useAutoSalvar({
  assinatura,
  pronto,
  jaSalvo,
  salvar,
  atraso = 900,
}: {
  /** Representação dos valores atuais do cartão (muda quando algum campo muda). */
  assinatura: string;
  /** Todos os campos obrigatórios válidos. */
  pronto: boolean;
  /** O cartão já veio do banco com estes valores (não precisa gravar ao abrir). */
  jaSalvo: boolean;
  /** Grava no banco; devolve true se deu certo. */
  salvar: () => Promise<boolean>;
  atraso?: number;
}) {
  const [salvaEm, setSalvaEm] = useState<string | null>(jaSalvo ? assinatura : null);
  const [falhouEm, setFalhouEm] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);

  // Valores mais recentes, para o temporizador e para o salvamento ao sair da tela.
  const ultimo = useRef({ assinatura, pronto, salvar });
  const salvaRef = useRef<string | null>(jaSalvo ? assinatura : null);
  const falhouRef = useRef<string | null>(null);
  const emCurso = useRef<Promise<void> | null>(null);
  const descartado = useRef(false);
  useEffect(() => {
    ultimo.current = { assinatura, pronto, salvar };
  });

  const executar = useCallback(async (): Promise<void> => {
    if (emCurso.current) {
      await emCurso.current;
    }
    const { assinatura: a, pronto: p, salvar: s } = ultimo.current;
    if (descartado.current || !p || a === salvaRef.current || a === falhouRef.current) return;
    const tarefa = (async () => {
      setSalvando(true);
      const ok = await s();
      if (ok) {
        salvaRef.current = a;
        falhouRef.current = null;
        setSalvaEm(a);
        setFalhouEm(null);
      } else {
        falhouRef.current = a;
        setFalhouEm(a);
      }
      setSalvando(false);
    })();
    emCurso.current = tarefa;
    await tarefa;
    emCurso.current = null;
  }, []);

  // Grava depois de uma pausa na digitação (e de novo se algo mudou enquanto gravava).
  useEffect(() => {
    if (!pronto || salvando || assinatura === salvaEm || assinatura === falhouEm) return;
    const t = setTimeout(() => void executar(), atraso);
    return () => clearTimeout(t);
  }, [assinatura, pronto, salvando, salvaEm, falhouEm, atraso, executar]);

  // "Continuar" pode pedir para gravar já; ao sair da tela, grava o que ficou pendente.
  useEffect(() => {
    pendentes.add(executar);
    return () => {
      pendentes.delete(executar);
      void executar();
    };
  }, [executar]);

  const estado: EstadoAutoSalvar = salvando
    ? "salvando"
    : !pronto
      ? "incompleto"
      : assinatura === salvaEm
        ? "salvo"
        : assinatura === falhouEm
          ? "erro"
          : "pendente";

  /** Chamar antes de remover o cartão: impede que ele seja gravado ao sair da tela. */
  const descartar = useCallback(() => {
    descartado.current = true;
  }, []);

  return { estado, descartar };
}
