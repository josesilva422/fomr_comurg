import { CursosCatalogoLista } from "./CursosCatalogoLista";

export const metadata = { title: "Cursos fora do catálogo · Painel da Comissão", robots: { index: false, follow: false } };

export default function CursosCatalogoPage() {
  return (
    <div className="card">
      <header className="step-head">
        <p className="eyebrow">Análise curricular · Formação adicional</p>
        <h2>Cursos e certificações fora do catálogo</h2>
        <p className="lead">
          A lista de cursos e certificações pontuáveis por Grupo (Anexo I, item 2.1) é <b>exemplificativa</b>: um item fora dela só pontua se a Comissão
          deliberar de forma motivada que o conteúdo programático guarda correlação direta com o Grupo. Enquanto não houver deliberação, o item pontua
          normalmente (pendente de confirmação); recusar o item zera a pontuação dele, sem consumir a faixa de carga horária de outros cursos do candidato.
        </p>
      </header>
      <CursosCatalogoLista />
    </div>
  );
}
