-- Remove a aba de formulário. painel.relatorio_respostas volta a ser a versão da migração 20260923100000
-- (reaplique-a se precisar do corpo antigo); aqui só removemos as funções novas.
drop function if exists painel.formulario_da_inscricao(uuid);
-- ATENÇÃO: painel.relatorio_respostas chama interno.registro_formulario; só remova esta depois de restaurar aquela.
drop function if exists interno.registro_formulario(uuid);
