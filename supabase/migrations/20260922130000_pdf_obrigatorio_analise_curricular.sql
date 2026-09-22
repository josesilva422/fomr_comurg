-- Documentos que entram na análise curricular (habilitação + pontuação do Anexo I) só podem ser PDF —
-- decisão do responsável em 22/09/2026. Documentos que não entram na análise curricular (identidade, CPF,
-- laudo PcD, autodeclaração racial, comprovante de Pix, requerimento de isenção) continuam aceitando
-- PDF, JPG ou PNG (o próprio edital, item 4.9.3, permite imagem para o comprovante de Pix).
--
-- A trava fica no banco (não só na interface), seguindo o mesmo princípio já usado para o prazo de
-- inscrições (CLAUDE.md, princípio 5: "o bloqueio é no backend, com horário do servidor, nunca só na
-- interface").

alter table publico.documentos
  add constraint ck_pdf_obrigatorio_analise_curricular check (
    tipo not in (
      'diploma_graduacao', 'diploma_pos', 'diploma_mestrado', 'diploma_doutorado',
      'certificado_curso', 'certificacao_profissional',
      'experiencia_ctps', 'experiencia_declaracao', 'experiencia_contrato',
      'experiencia_publica', 'experiencia_autonomo',
      'art_rrt_acervo', 'declaracao_lideranca',
      'historico_escolar', 'revalidacao_diploma', 'traducao_juramentada',
      'curriculo_anexo_v'
    )
    or mime = 'application/pdf'
  );
