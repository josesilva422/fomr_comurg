"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

interface ResultadoCandidato {
  etapa: "ac_preliminar" | "ac_definitivo" | "entrevista_preliminar" | "resultado_final";
  pontuacao: number | null;
  posicao: number | null;
  situacao: string;
  motivacao: string | null;
  publicado_em: string;
}

const fmt = (v: string) => new Date(v).toLocaleString("pt-BR", { dateStyle: "long", timeStyle: "short", timeZone: "America/Sao_Paulo" });

/** Resultados já publicados pela Comissão para a PRÓPRIA inscrição (publico.resultados_candidato). */
export function useMeusResultados(ativo: boolean) {
  const [res, setRes] = useState<ResultadoCandidato[]>([]);

  const buscar = useCallback(async () => {
    const { data } = await createClient()
      .from("resultados_candidato")
      .select("etapa, pontuacao, posicao, situacao, motivacao, publicado_em")
      .order("publicado_em");
    return (data as ResultadoCandidato[] | null) ?? [];
  }, []);

  useEffect(() => {
    if (!ativo) return;
    let vivo = true;
    void buscar().then((r) => {
      if (vivo) setRes(r);
    });
    return () => {
      vivo = false;
    };
  }, [ativo, buscar]);

  return res;
}

// Resultado da análise curricular (Anexo IV, itens 14 e 17), visto só pela própria inscrição, no que a
// Comissão publicou: pontuação, posição, situação e motivação (edital 7.3, 13.2, 13.3).
export function ResultadoAC({ resultados }: { resultados: ResultadoCandidato[] }) {
  const preliminar = resultados.find((r) => r.etapa === "ac_preliminar");
  const definitivo = resultados.find((r) => r.etapa === "ac_definitivo");
  if (!preliminar && !definitivo) return null;
  const atual = definitivo ?? preliminar!;

  return (
    <section className="card" style={{ marginTop: 16 }}>
      <h3>Resultado da análise curricular</h3>
      <p>
        <b>{definitivo ? "Resultado definitivo" : "Resultado preliminar"}</b> — {atual.situacao}
        {atual.posicao ? `, ${atual.posicao}º lugar no Grupo e Nível` : ""}
        {atual.pontuacao !== null ? ` (${Number(atual.pontuacao).toFixed(1)} pontos na análise curricular)` : ""}. Publicado em {fmt(atual.publicado_em)}.
      </p>
      {atual.motivacao ? <p className="hint">Motivo registrado pela Comissão: {atual.motivacao}</p> : null}
      {definitivo ? (
        <p className="hint">
          Cabe recurso contra o resultado definitivo da análise curricular (item 9.1, alínea c do edital), no prazo de 3 dias úteis contados do dia útil
          seguinte à publicação. O recurso é enviado exclusivamente pelo e-mail pss2026comurg@comurg.com.br, com o formulário do Anexo VI preenchido e
          assinado, e &quot;RECURSO&quot;, a etapa, o seu nome e o Grupo/Nível no assunto (item 9.2).
        </p>
      ) : preliminar ? (
        <p className="hint">
          Cabe recurso contra o resultado preliminar da análise curricular (item 9.1, alínea c do edital), no prazo de 3 dias úteis contados do dia útil
          seguinte à publicação. O recurso é enviado exclusivamente pelo e-mail pss2026comurg@comurg.com.br, com o formulário do Anexo VI preenchido e
          assinado, e &quot;RECURSO&quot;, a etapa, o seu nome e o Grupo/Nível no assunto (item 9.2).
        </p>
      ) : null}
    </section>
  );
}
