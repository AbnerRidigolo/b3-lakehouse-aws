# Fase 1: fundação (implementação local)

Status: código em validação, ainda não implantado. Push e configuração no GitHub não realizados.

## Escopo

- `infra/bootstrap`: bucket privado de estado com AES256, versionamento e TLS; GitHub OIDC; papéis separados de plan/apply.
- `infra/environments/dev`: dois alertas de custo CUSTOM para o intervalo total do projeto, teto USD 10 antes de créditos. Um filtro pelo projeto e outro por toda a conta para cobrir tags ainda não ativadas. O segundo inclui gastos de outros projetos.
- `infra/modules/budget`: alertas por e-mail, sem relatórios pagos nem ações automáticas.
- CI offline e workflow de plan/apply/destroy protegido por environments.
- Nenhum serviço de dados, Organizations ou Identity Center.

## Limites

USD 10 é teto total, não mensal. Reservar USD 2 para limpeza, latência de faturamento e imprevistos. A previsão conservadora de gasto acumulado + pendente + próxima operação não pode superar USD 8 durante a implementação. Budget não é bloqueio de cobrança e tem atraso. Não há garantia de que o histórico completo e todas as tecnologias caibam nesse valor: medir um dia e um ano antes de autorizar expansão. Redshift permanece opcional e não implementado.

```powershell
python scripts/cost_gate.py --spent 0 --pending 0 --estimate 0.10
```

Os números acima são exemplo de cálculo, não custo observado. Registrar também custos de GitHub Actions caso o plano do GitHub os cobre.

## Antes do primeiro apply

1. Confirmar região dos recursos: proposta original us-east-1; us-east-2 foi usada somente para login.
2. Revisar políticas IAM e verificar se já existe provider GitHub OIDC. Se existir, passar seu ARN, sem recriá-lo ou modificar sua confiança.
3. Criar `terraform.tfvars` local a partir do exemplo; o e-mail real fica no arquivo ignorado.
4. Confirmar datas do orçamento, nome global do bucket e identidade da sessão temporária.
5. Gerar e revisar plano local do bootstrap. Apresentar estimativa de S3 (armazenamento de todas as versões e requisições) e obter aprovação específica.
6. Proprietário aplica bootstrap localmente, como definido no escopo original. Não usar auto-approve.
7. Preservar e proteger estado do bootstrap. Após verificar bucket, migrar com backend S3 separado (`bootstrap/terraform.tfstate`), usando sessão local; papéis CI só acessam `dev/terraform.tfstate`. A migração é uma etapa explícita posterior ao primeiro apply, não automática.
8. Inicializar dev com os outputs do bootstrap e configurar budgets. Não habilitar CI de implantação antes dos environments estarem protegidos.

## Acesso local e compatibilidade Terraform

O login `b3-dev` já foi validado na CLI. Para ferramentas que não reconheçam `login_session`, configurar OUTRO perfil no arquivo de configuração AWS do usuário com `credential_process` que chame o executável oficial absoluto e `aws configure export-credentials --profile b3-dev --format process`. Não imprimir essa saída, não usar o perfil de destino como origem (recursão), não versionar configuração pessoal. Validar compatibilidade antes do plan autenticado. Não gerar access keys permanentes.

## GitHub: configuração obrigatória pelo proprietário

Criar environments:

- `aws-plan`: revisão obrigatória antes de executar código de PR com OIDC. Permitir PRs internos e main conforme regras de deployment disponíveis.
- `aws-apply`: revisão obrigatória por pessoa autorizada; restringir deployment a main. Essa aprovação vem DEPOIS do plano da mesma execução, que será aplicado sem regeneração.

Não habilitar `DEPLOY_ENABLED` se o plano do GitHub não oferecer a proteção necessária. O valor é ausente/false por padrão. Nesse caso manter implantação manual até decisão explícita.

Variáveis do repositório: `AWS_ACCOUNT_ID`, `AWS_REGION`, `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`, `PROJECT_START`, `PROJECT_END`, `DEPLOY_ENABLED`.

Secret: `BUDGET_ALERT_EMAIL` (dado de contato, não credencial AWS).

PRs de forks executam apenas CI offline. PRs internos só recebem papel plan após aprovação. Não usar `pull_request_target`. O papel plan não grava o estado e o papel apply só administra os budgets da Fase 1; não pode alterar o próprio IAM nem o bootstrap. Permissões para fases futuras serão adicionadas sob revisão.

O plano binário contém valores sensíveis, inclusive e-mail e potencialmente estado: guardar apenas como artifact do run por um dia, nunca como comentário público ou arquivo Git. Aprovar somente após examinar mudanças e estimativa. Reexecutar plan se o estado mudar; não forçar plano obsoleto.

## Destroy

Workflow manual, somente main, confirmação exata `DESTROY b3-lakehouse-aws` e aprovação do plano no environment apply. Remove somente os recursos dev, atualmente budgets. Não remove bucket de estado ou OIDC. Recursos compartilhados, versões do estado e bootstrap requerem plano de encerramento separado e autorização do proprietário.

## Evidências ainda pendentes

Plan autenticado, apply, alertas recebidos, backend remoto, autenticação GitHub OIDC e execução de workflows. Testes locais não comprovam nenhum desses itens.

## Referências

- https://developer.hashicorp.com/terraform/language/backend/s3
- https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws
- https://docs.aws.amazon.com/service-authorization/latest/reference/list_budgets.html
- https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/
- https://aws.amazon.com/s3/pricing/
- https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html
