"use client";

import { useRef } from "react";

// Explica, em linguagem simples, como o sistema calcula habilitação, pontuação, convocação e classificação.
// Tudo aqui espelha o que está implementado no banco (interno.calcular_avaliacao, painel.listar_avaliacoes,
// painel.classificacao_final). Se a regra mudar lá, atualize este texto.
const VERSAO_MOTOR = "v3-2026-09-22";

export function MotorRegrasBotao() {
  const ref = useRef<HTMLDialogElement>(null);
  return (
    <>
      <button type="button" className="painel-nav-link painel-nav-botao" onClick={() => ref.current?.showModal()}>
        <span>Motor de regras</span>
        <small>Como as pontuações são calculadas</small>
      </button>

      <dialog
        ref={ref}
        className="modal-motor"
        aria-labelledby="motor-titulo"
        onClick={(e) => {
          // clique no fundo escurecido (fora da caixa) fecha
          if (e.target === ref.current) ref.current?.close();
        }}
      >
        <div className="modal-motor-caixa">
          <header className="modal-motor-topo">
            <div>
              <h2 id="motor-titulo">Motor de regras</h2>
              <p className="hint" style={{ margin: 0 }}>
                Como a habilitação, a pontuação e a classificação são calculadas · motor da análise curricular {VERSAO_MOTOR}
              </p>
            </div>
            <button type="button" className="btn btn-sm" onClick={() => ref.current?.close()} aria-label="Fechar">
              Fechar ✕
            </button>
          </header>

          <div className="modal-motor-corpo">
            <div className="legenda-siglas" aria-label="Legenda das siglas">
              <b>Legenda</b>
              <span>
                <strong>AC</strong> Análise Curricular <em>(máx. 60 pontos)</em>
              </span>
              <span>
                <strong>ET</strong> Entrevista Técnica <em>(máx. 40 pontos)</em>
              </span>
              <span>
                <strong>PF</strong> Pontuação Final = AC + ET <em>(máx. 100 pontos)</em>
              </span>
            </div>

            <div className="alert alert-ok">
              <p>
                <b>A IA não dá nota.</b> Todas as pontuações são calculadas por regras fixas (código), sempre com o mesmo resultado para os mesmos dados. A IA só
                lê documentos e aponta se conferem com o que o candidato declarou. Os resultados são <b>rascunho</b> até a Comissão revisar e aprovar; cada
                cálculo guarda o detalhamento, o motivo de cada item que não pontuou e a versão do motor.
              </p>
            </div>

            <h3>1. Habilitação (sim ou não, não gera pontos)</h3>
            <p className="hint">Falhar em qualquer requisito abaixo torna o candidato inabilitado (edital 6.3.3).</p>
            <table className="tabela">
              <thead>
                <tr>
                  <th>Requisito</th>
                  <th>Regra aplicada</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>Graduação</td>
                  <td>Tecnólogo não é aceito (5.1.6) e o curso precisa constar na lista aceita para o Grupo e o Nível (3.2 a 3.4).</td>
                </tr>
                <tr>
                  <td>Experiência mínima</td>
                  <td>
                    Júnior 12 meses · Pleno 48 meses · Sênior 96 meses. Conta a <b>união dos períodos em meses</b>: vínculos simultâneos valem uma só vez
                    (5.4), e vínculo ativo conta até o encerramento das inscrições. Só conta o vínculo com comprovante anexado (5.3): privado — CTPS,
                    declaração ou contrato; público — certidão/declaração do órgão ou contrato administrativo; autônomo — contrato/RPA/nota fiscal
                    <i>e</i> declaração do contratante. A validade do documento e a área da experiência são conferidas pela Comissão.
                  </td>
                </tr>
                <tr>
                  <td>Pós-graduação</td>
                  <td>
                    <b>Júnior:</b> não exige. <b>Pleno:</b> título de especialização <i>ou</i> 5 anos de experiência <i>ou</i> (só Grupo B) certificação
                    PMP/PgMP/PRINCE2/IPMA ativa, com credencial e código de verificação — se a especialização for o único meio de cumprir o requisito, ela não pontua
                    depois. <b>Sênior:</b> exige especialização (esse título não pontua depois). Só vale especialização com certificado anexado; no Pleno,
                    a experiência da equivalência só conta com comprovantes e a certificação só com o certificado anexado.
                  </td>
                </tr>
              </tbody>
            </table>

            <h3>2. Análise curricular — AC (máximo 60 pontos)</h3>
            <p className="hint">Só pontua o que excede o requisito mínimo, e nada é contado duas vezes (6.4.3). Anexo I do edital.</p>

            <h4>Formação adicional — máx. 10,0</h4>
            <ul>
              <li>Especialização/MBA (mínimo 360h): <b>2,0</b> por título, <b>sem limite de quantidade</b> (só o teto de 10,0).</li>
              <li>Mestrado: <b>3,0</b> (1 título). Doutorado: <b>4,0</b> (1 título).</li>
              <li>Só conta o que foi concluído até 28/09/2026 (publicação do edital) e que tem <b>documento anexado</b>.</li>
            </ul>

            <h4>Cursos e certificações — máx. 15,0 (teto rígido)</h4>
            <table className="tabela">
              <thead>
                <tr>
                  <th>Tipo</th>
                  <th>Pontos por item</th>
                  <th>Limite da faixa</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>Curso de 20 a 39 horas</td>
                  <td>1,0</td>
                  <td>até 5,0</td>
                </tr>
                <tr>
                  <td>Curso de 40 a 79 horas</td>
                  <td>2,0</td>
                  <td>até 6,0</td>
                </tr>
                <tr>
                  <td>Curso de 80 horas ou mais</td>
                  <td>3,0</td>
                  <td>até 9,0</td>
                </tr>
                <tr>
                  <td>Certificação profissional</td>
                  <td>5,0</td>
                  <td>limitada ao teto de 15,0</td>
                </tr>
              </tbody>
            </table>
            <p className="hint">
              Também exige documento anexado e conclusão até 28/09/2026. Curso fora do catálogo do Grupo (item 2.1) ainda pontua, mas fica sinalizado para a
              Comissão confirmar a correlação.
            </p>

            <h4>Experiência específica — máx. 35,0 (por degrau, não proporcional)</h4>
            <table className="tabela">
              <thead>
                <tr>
                  <th>Tempo que excede o mínimo do nível</th>
                  <th>Pontos</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>de 1 a 12 meses (sem excedente, 0 ponto)</td>
                  <td>5,0</td>
                </tr>
                <tr>
                  <td>de 13 a 36 meses</td>
                  <td>15,0</td>
                </tr>
                <tr>
                  <td>de 37 a 60 meses</td>
                  <td>25,0</td>
                </tr>
                <tr>
                  <td>mais de 60 meses</td>
                  <td>35,0</td>
                </tr>
              </tbody>
            </table>

            <h3>3. Convocação para a entrevista</h3>
            <ul>
              <li>Candidato <b>habilitado</b> e com <b>AC de 35 pontos ou mais</b> (6.4.4).</li>
              <li>
                Até <b>3 candidatos por vaga</b> do Grupo e Nível (6.5.1), do maior para o menor AC. Quem empata na última posição também é convocado.
              </li>
            </ul>

            <h3>4. Entrevista técnica — ET (máximo 40 pontos)</h3>
            <ul>
              <li>
                Seis competências: Domínio técnico (10), Análise e resolução de problemas (10), Planejamento e priorização (5), Comunicação (5), Caso técnico
                (5) e Postura e aderência (5). Nota inteira, com justificativa obrigatória.
              </li>
              <li>
                <b>ET = média</b> das notas totais dos avaliadores (6.5.5), e a banca tem no mínimo 3 membros (6.5.2). Cada avaliador envia a própria ficha (no máximo 10 por candidato) e ninguém vê a nota de outro avaliador; a média só aparece a partir de 3 fichas.
              </li>
              <li>Abaixo de 15 pontos o edital prevê eliminação (6.5.7): o sistema <b>só sinaliza</b>, a decisão é da Comissão.</li>
            </ul>

            <h3>5. Pontuação final e classificação</h3>
            <p>
              <b>PF = AC + ET</b> (máximo 100), classificado por Grupo e Nível. Empates de PF são resolvidos, nesta ordem (7.2): idade de 60 anos ou mais (o mais
              velho), maior nota na entrevista, maior pontuação em experiência, maior total da AC, graduação mais antiga e maior idade.
            </p>

            <h3>Convenções assumidas (a confirmar)</h3>
            <ul>
              <li>No nível Pleno, quando há a especialização <i>e também</i> a equivalência (5 anos de experiência ou, no Grupo B, certificação ativa), a
                especialização pontua. Quando ela é o único meio de cumprir o requisito, não pontua (Anexo I, item 1; 6.4.3).</li>
              <li>A idade de 60 anos do desempate é contada na data de encerramento das inscrições.</li>
              <li>
                A correlação de cursos e títulos com as atribuições do Grupo e a autenticidade dos diplomas (e-MEC, Diplomas Digitais) são conferidas pela
                Comissão, não pelo motor.
              </li>
            </ul>
          </div>
        </div>
      </dialog>
    </>
  );
}
