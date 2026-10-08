# B3 Lakehouse AWS

Projeto em preparação para ingestão de cotações B3 e séries do Banco Central, processamento Spark e tabelas Apache Iceberg consultáveis no Athena.

**Estado atual: fundação, bronze e silver incremental implantadas em us-east-1. Data 01/10/2026 carregada em duas tabelas Iceberg v2 pelo Glue: 317 cotações e 3 taxas. Repetição MERGE validada sem duplicação. Scheduler permanece desativado. Computação estimada das duas chamadas Glue: USD 0,06417; budget da conta ainda informa USD 0,335 com atraso; custo final por serviço pendente.**

## Arquitetura planejada

- EventBridge Scheduler e Step Functions para orquestração.
- Lambda para ingestão em S3 bronze.
- Glue PySpark para incremental e backfill 2025 autorizado; EMR Serverless preparado, com criação bloqueada por habilitação da conta.
- Iceberg e Glue Data Catalog para silver e gold.
- dbt com Athena em uma tarefa ECS Fargate, com imagem no ECR.
- DynamoDB para controle de execução; SQS, SNS e CloudWatch para falhas e observabilidade.
- Terraform e GitHub Actions com OIDC para infraestrutura.

Bootstrap, budgets, workflows, ingestão bronze e silver incremental estão implantados. EMR/histórico, gold e orquestração ponta a ponta permanecem planejados.

## Preparação local

No PowerShell, execute a verificação offline:

```powershell
.\scripts\check-environment.ps1
```

O script verifica ferramentas locais. Não acessa a AWS, não instala programas e não lê arquivos de credenciais.

Leia [o estado da Fase 0](docs/phase-0.md) antes de prosseguir.

## Regras de execução

- Região da fundação: `us-east-1`. Disponibilidade e custos dos serviços das próximas fases serão verificados antes da implantação.
- Aprovação explícita antes de cada operação com custo e ao final de cada fase.
- Push somente com autorização por commit; PR e merge realizados pelo proprietário.
- Sem chaves estáticas AWS no código ou GitHub. Acesso local por `aws login` com credenciais temporárias e CI por OIDC. Identity Center e Organizations não serão habilitados para este projeto.
- Sem NAT Gateway, MWAA, clusters fixos ou RDS.
- Redshift Serverless opcional, desligado por padrão.
- Testes automatizados offline, sem chamadas reais à AWS ou internet.
- Publicar apenas evidências verificadas; separar planejamento, implantação e validação.

## Fases

0. Acesso temporário via IAM — validado.
1. Fundação e CI/CD — bootstrap e budgets implantados; CI e OIDC validados; plan/apply e artifact criptografado validados.
2. Ingestão bronze — implantada e validada com carga real e idempotência; Scheduler criado e desativado.
3. Silver incremental — implantada e validada com carga e repetição MERGE no Glue/Iceberg. EMR 2025 bloqueado por habilitação da conta; alternativa Glue autorizada e preparada, com implantação e execução pendentes. Histórico completo ainda não implementado.
4. Gold com dbt — pendente.
5. Orquestração e confiabilidade — pendente.
6. Evidências, documentação e custos — pendente.
7. Redshift opcional — pendente de decisão.


## Fundação para revisão

Consulte [Fase 1](docs/phase-1.md) e [estimativa inicial](docs/costs/foundation.md). Teto total: USD 10, com reserva de USD 2; não é teto mensal. Workflows habilitados, com revisão obrigatória nos environments de plan e apply.

Consulte [as evidências de validação da fundação e consumo observado](docs/foundation-validation.md).

A [fase 2](docs/phase-2.md) prepara Lambda, S3 bronze, DynamoDB e Scheduler. As flags de implantação e agendamento começam desativadas. Consulte [a estimativa da carga inicial](docs/costs/bronze.md) antes de autorizar recursos.

Consulte [as evidências da primeira carga bronze real](docs/bronze-data-evidence.md).

Consulte [a fase silver incremental](docs/phase-3.md), [a estimativa aprovada do piloto](docs/costs/silver.md) e [as evidências das duas execuções Glue](docs/silver-data-evidence.md). Silver habilitada no ambiente implantado, job sob demanda; defaults Terraform permanecem desativados para novos ambientes.

Consulte [o piloto histórico 2025 para revisão](docs/history-2025.md) e [sua estimativa](docs/costs/history.md). Fontes anuais preparadas e validadas localmente; nenhum backfill EMR executado.

[Backfill 2025 no Glue autorizado para preservar o plano FREE](docs/history-glue.md). Nenhum job histórico executado ainda.
