# Fase 0: preparação e critérios de conclusão

## Verificado em 30/09/2026

- Repositório remoto vazio, clonado localmente.
- Branch local: `codex/fase-0-preparacao`.
- Git e Python encontrados.
- Comando antigo `aws` no PATH falha; usar o executável oficial pelo caminho absoluto até corrigir a resolução.
- AWS CLI 2.37.6 instalada e validada no caminho padrão do Windows.
- Terraform não encontrado no PATH.
- Nenhuma ação de implantação ou execução de dados realizada.

## Informado pelo proprietário, ainda sem validação técnica local

- Conta AWS existente.
- MFA do root habilitado.
- Correção informada pelo proprietário: Identity Center desativado, sem portal SSO. Região selecionada no console: Ohio (us-east-2).

## Pendências

- Free Tier confirmado pelo proprietário; preservar plano e créditos. Nenhuma criação ou adesão a Organizations autorizada.
- Instalação da AWS CLI v2 concluída.
- Perfil `b3-dev` configurado via `aws login`; credenciais temporárias.
- Proprietário autenticou no navegador; identidade do usuário IAM esperado validada por STS.
- Confirmar proteção do acesso diário e troca da senha anteriormente exposta, sem registrar seu valor.
- Definir teto mensal e limites por experimento antes de preparar recursos pagos.

## Autenticação temporária após instalar a CLI v2

```powershell
aws login --profile b3-dev --region us-east-2
aws sts get-caller-identity --profile b3-dev
```

Ohio é utilizada nesta autenticação conforme o console atual; isso não autoriza mudar a região de implantação proposta (us-east-1). A autenticação deve ser concluída pelo proprietário. Não versionar tokens, saída com informações de conta ou configuração pessoal.

## Atenção ao plano

No Free Plan atual, aderir ao AWS Organizations pode causar conversão para o plano pago e encerramento dos créditos do Free Tier. Conferir o estado atual antes de mudar qualquer configuração de organização. Não é possível presumir benefícios apenas pelo termo “Free Tier”.

Fontes:
- https://aws.amazon.com/free/free-tier-faqs/
- https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html

## Critério de saída

CLI v2 funcional, autenticação temporária validada, conta/plano conferidos e confirmação do proprietário para iniciar a Fase 1. A instalação do Terraform é requisito para a fase seguinte.

## Custos

Nenhum recurso AWS criado ou job executado nesta preparação. O faturamento existente da conta ainda não foi consultado; não há afirmação sobre seu saldo ou custo total.

## Permissão de login local

O usuário IAM precisa das permissões de SignInLocalDevelopmentAccess ou equivalentes. Não alterar permissões automaticamente: se houver AccessDenied, revisar a necessidade antes de conceder acesso. Usar o usuário IAM diário, não o root. Terraform e SDKs podem requerer perfil credential_process compatível; nunca executar export-credentials para imprimir tokens no terminal.


## Validação do acesso concluída

Login temporário e consulta STS concluídos com sucesso. Nenhuma infraestrutura criada e nenhuma configuração do plano alterada. Aguardando aprovação para iniciar a Fase 1 e definição do teto mensal. Dados de saldo e validade permanecem informações fornecidas pelo proprietário, não consultadas via API.
