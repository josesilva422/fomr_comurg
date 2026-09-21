// O schema `publico` ainda não tem tipos gerados (o gerador só cobre `public`),
// então o cliente é tipado de forma permissiva. As interfaces de domínio estão em lib/tipos.ts.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Banco = any;
