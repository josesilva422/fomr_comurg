export const somenteDigitos = (v: string) => v.replace(/\D/g, "");

/** Valida os dígitos verificadores do CPF (mesma regra do banco: publico.cpf_valido). */
export function cpfValido(valor: string): boolean {
  const d = somenteDigitos(valor);
  if (d.length !== 11 || /^(\d)\1+$/.test(d)) return false;
  const digito = (tam: number) => {
    let soma = 0;
    for (let i = 0; i < tam; i++) soma += Number(d[i]) * (tam + 1 - i);
    const r = (soma * 10) % 11;
    return r === 10 ? 0 : r;
  };
  return digito(9) === Number(d[9]) && digito(10) === Number(d[10]);
}

export function mascaraCPF(v: string): string {
  const d = somenteDigitos(v).slice(0, 11);
  return d
    .replace(/(\d{3})(\d)/, "$1.$2")
    .replace(/(\d{3})(\d)/, "$1.$2")
    .replace(/(\d{3})(\d{1,2})$/, "$1-$2");
}

export function mascaraTelefone(v: string): string {
  const d = somenteDigitos(v).slice(0, 11);
  if (d.length > 10) return d.replace(/(\d{2})(\d{5})(\d{4})/, "($1) $2-$3");
  if (d.length > 6) return d.replace(/(\d{2})(\d{4})(\d{0,4})/, "($1) $2-$3");
  if (d.length > 2) return d.replace(/(\d{2})(\d+)/, "($1) $2");
  return d;
}

/** Datas do processo (edital, Anexo IV). O banco é a fonte da verdade do período. */
export const DATA_ENCERRAMENTO = "2026-10-13";
/** Idade mínima é avaliada na data de encerramento das inscrições (item 3.1). */
export const NASCIMENTO_MAXIMO = "2008-10-13";

export const emailValido = (v: string) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v.trim());

export interface ErroBanco {
  code?: string;
  message?: string;
  hint?: string | null;
  details?: string | null;
}

/** Traduz erros do banco (RLS, checks, trava de prazo) para mensagens claras ao candidato. */
export function traduzirErro(e: ErroBanco | null | undefined): string {
  if (!e) return "";
  const texto = `${e.message ?? ""} ${e.hint ?? ""} ${e.details ?? ""}`;
  if (e.code === "23505" && /cpf/i.test(texto)) return "Este CPF já está cadastrado em outra conta.";
  if (e.code === "23514" && /cpf/i.test(texto)) return "CPF inválido. Confira os números digitados.";
  if (e.code === "23514" && /nome/i.test(texto)) return "Informe o nome completo, com sobrenome.";
  if (e.code === "23514" && /telefone/i.test(texto)) return "Informe o telefone com DDD.";
  if (/inscricoes_fora_do_periodo|Fora do período/i.test(texto)) return "As inscrições não estão abertas no momento.";
  if (e.code === "42501" || /row-level security|permission denied/i.test(texto))
    return "Não foi possível salvar: a inscrição pode já ter sido enviada.";
  return "Não foi possível salvar agora. Tente novamente em instantes.";
}
