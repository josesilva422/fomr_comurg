# Configurar o e-mail que envia o código de login

O candidato entra digitando um código enviado por e-mail (sem senha). O Supabase precisa de um servidor SMTP próprio
para enviar esse código — o envio embutido dele só funciona para os e-mails da própria organização.

**Preciso de três informações da conta Umbler** (host, porta e o endereço que vai remeter os e-mails). A **senha você
digita direto no painel do Supabase** — essa é a única parte que não faço por você, mesmo com autorização, porque não
insiro senhas em nenhum painel.

## O que me passar

| Campo | Onde achar na Umbler | Exemplo |
|---|---|---|
| Servidor SMTP (host) | Painel da Umbler → E-mail → Configurações do cliente de e-mail | `smtp.umbler.com` |
| Porta | Junto com o host (geralmente 465 com SSL, ou 587 com TLS) | `465` |
| Endereço remetente | O e-mail que vai enviar os códigos | `inscricoes@comurg.go.gov.br` (exemplo) |

## O que eu faço com isso

Preparo o passo a passo exato do painel do Supabase (`Authentication → Emails → SMTP Settings`), com cada campo já
preenchido — falta só você colar a senha e clicar em salvar.

## O que também precisa mudar (eu oriento, você confirma)

Além de ligar o SMTP, é preciso trocar o **modelo do e-mail** para mostrar o código em vez de só um link de
confirmação. Isso já foi confirmado como o problema em 22/09/2026: o e-mail chegava, mas sem o código.

Em `Authentication → Emails → Templates`, edite **os dois modelos abaixo** (o Supabase usa um ou outro dependendo
se é a primeira vez do candidato ou não — dá para não saber qual vai disparar, então os dois precisam mostrar o
código):

**1. Confirm signup** (dispara no primeiro login de cada candidato — o mais comum)
Suporte não mostra {{ .Token }} por padrão. Troque o corpo por algo como:

> Seu código de acesso ao PSS COMURG 2026 é: **{{ .Token }}**
> Ele vale por 15 minutos. Se você não solicitou este código, ignore este e-mail.

**2. Magic Link** (dispara nos logins seguintes do mesmo candidato)
Mesmo texto:

> Seu código de acesso ao PSS COMURG 2026 é: **{{ .Token }}**
> Ele vale por 15 minutos. Se você não solicitou este código, ignore este e-mail.

Salve os dois. Não precisa mexer em "Reset Password", "Change Email Address" nem "Invite user" — o portal do
candidato não usa esses fluxos.

## Teste antes de divulgar

Depois de configurado, teste com um e-mail seu: peça o código na tela de login e confira se chegou (olhe também o
spam). Se o código ainda não aparecer, confira se salvou os DOIS modelos (não só um) e se o texto tem exatamente
`{{ .Token }}`, com os pontos e as chaves duplas.
