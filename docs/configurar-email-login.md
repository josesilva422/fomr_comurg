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

Além de ligar o SMTP, é preciso trocar o **modelo do e-mail** para mostrar o código em vez de um link de confirmação
de cadastro. Em `Authentication → Emails → Templates`, no modelo **Magic Link**, o corpo do e-mail precisa conter
`{{ .Token }}` (o código de 6 dígitos que o candidato digita na tela). Um texto simples como:

> Seu código de acesso ao PSS COMURG 2026 é: **{{ .Token }}**
> Ele vale por 15 minutos.

## Teste antes de divulgar

Depois de configurado, teste com um e-mail seu: peça o código na tela de login e confira se chegou (olhe também o
spam). Se não chegar, o erro mais comum é host/porta errados ou a senha não ter sido salva.
