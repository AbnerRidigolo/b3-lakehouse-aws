# B3 Lakehouse AWS

Projeto em preparação para ingestão de cotações B3 e séries do Banco Central, processamento Spark e tabelas Apache Iceberg consultáveis no Athena.

**Estado atual: acesso temporário validado; Fase 1 implementada e validada localmente, aguardando aprovação de implantação. Nenhuma infraestrutura aplicada, nenhum dado carregado e nenhum custo de execução medido.**

## Arquitetura planejada

- EventBridge Scheduler e Step Functions para orquestração.
- Lambda para ingestão em S3 bronze.
- Glue PySpark para incremental e EMR Serverless para histórico sob demanda.
- Iceberg e Glue Data Catalog para silver e gold.
- dbt com Athena em uma tarefa ECS Fargate, com imagem no ECR.
- DynamoDB para controle de execução; SQS, SNS e CloudWatch para falhas e observabilidade.
- Terraform e GitHub Actions com OIDC para infraestrutura.

O bootstrap, os budgets e os workflows estão implementados localmente. Os componentes de dados permanecem planejados; nenhum componente foi implantado.

## Preparação local

No PowerShell, execute a verificação offline:

```powershell
.\scripts\check-environment.ps1
```

O script verifica ferramentas locais. Não acessa a AWS, não instala programas e não lê arquivos de credenciais.

Leia [o estado da Fase 0](docs/phase-0.md) antes de prosseguir.

## Regras de execução

- Região proposta: `us-east-1`, sujeita à confirmação de disponibilidade e custos.
- Aprovação explícita antes de cada operação com custo e ao final de cada fase.
- Push somente com autorização por commit; PR e merge realizados pelo proprietário.
- Sem chaves estáticas AWS no código ou GitHub. Acesso local por `aws login` com credenciais temporárias e CI por OIDC. Identity Center e Organizations não serão habilitados para este projeto.
- Sem NAT Gateway, MWAA, clusters fixos ou RDS.
- Redshift Serverless opcional, desligado por padrão.
- Testes automatizados offline, sem chamadas reais à AWS ou internet.
- Publicar apenas evidências verificadas; separar planejamento, implantação e validação.

## Fases

0. Acesso temporário via IAM — validado.
1. Fundação e CI/CD — código local validado; implantação pendente.
2. Ingestão bronze — pendente.
3. Silver e backfill — pendente.
4. Gold com dbt — pendente.
5. Orquestração e confiabilidade — pendente.
6. Evidências, documentação e custos — pendente.
7. Redshift opcional — pendente de decisão.


## Fundação para revisão

Consulte [Fase 1](docs/phase-1.md) e [estimativa inicial](docs/costs/foundation.md). Teto total: USD 10, com reserva de USD 2; não é teto mensal. Workflows de implantação desabilitados até configuração e proteção dos environments.
