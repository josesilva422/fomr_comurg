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
function OrientacaoRecurso({ alinea }: { alinea: string }) {
  return (
    <p className="hint">
      Cabe recurso contra este resultado (item 9.1, alínea {alinea} do edital), no prazo de 3 dias úteis contados do dia útil seguinte à publicação. O
      recurso é enviado exclusivamente pelo e-mail pss2026comurg@comurg.com.br, com o formulário do Anexo VI preenchido e assinado, e &quot;RECURSO&quot;, a
      etapa, o seu nome e o Grupo/Nível no assunto (item 9.2).
    </p>
  );
}

export function ResultadoAC({ resultados }: { resultados: ResultadoCandidato[] }) {
  const preliminar = resultados.find((r) => r.etapa === "ac_preliminar");
  const definitivo = resultados.find((r) => r.etapa === "ac_definitivo");
  const final = resultados.find((r) => r.etapa === "resultado_final");
  if (!preliminar && !definitivo && !final) return null;
  const atual = definitivo ?? preliminar;

  return (
    <>
      {atual ? (
        <section className="card" style={{ marginTop: 16 }}>
          <h3>Resultado da análise curricular</h3>
          <p>
            <b>{definitivo ? "Resultado definitivo" : "Resultado preliminar"}</b> — {atual.situacao}
            {atual.posicao ? `, ${atual.posicao}º lugar no Grupo e Nível` : ""}
            {atual.pontuacao !== null ? ` (${Number(atual.pontuacao).toFixed(1)} pontos na análise curricular)` : ""}. Publicado em{" "}
            {fmt(atual.publicado_em)}.
          </p>
          {atual.motivacao ? <p className="hint">Motivo registrado pela Comissão: {atual.motivacao}</p> : null}
          <OrientacaoRecurso alinea="c" />
        </section>
      ) : null}

      {final ? (
        <section className="card" style={{ marginTop: 16 }}>
          <h3>Resultado final do Processo Seletivo</h3>
          <p>
            <b>{final.situacao.charAt(0).toUpperCase() + final.situacao.slice(1)}</b>
            {final.posicao ? `, ${final.posicao}º lugar no Grupo e Nível` : ""}
            {final.pontuacao !== null ? ` (pontuação final ${Number(final.pontuacao).toFixed(1)})` : ""}. Publicado em {fmt(final.publicado_em)}.
          </p>
          {final.motivacao ? <p className="hint">Motivo registrado pela Comissão: {final.motivacao}</p> : null}
          {final.situacao === "cadastro de reserva" ? (
            <p className="hint">
              Candidatos do cadastro de reserva podem ser convocados se surgirem vagas, pela ordem de classificação (itens 2.1 e 11.1, minuta v11).
            </p>
          ) : null}
          <OrientacaoRecurso alinea="f" />
        </section>
      ) : null}
    </>
  );
}
