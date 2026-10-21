# Operação

Comandos para o **AWS CloudShell em us-east-1**, autenticado com credenciais temporárias. Cada comando que inicia processamento tem custo e exige aprovação prévia, conforme as [regras do projeto](../README.md#custo-e-regras-de-operação). Nada aqui deve ser automatizado no CI.

```bash
export AWS_REGION=us-east-1
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export TABLE=b3-lakehouse-aws-bronze-runs
export SFN=arn:aws:states:$AWS_REGION:$ACCOUNT:stateMachine:b3-lakehouse-aws-pipeline
```

## Leituras sem custo de processamento

```bash
# Prontidão (plano, budgets, ECS/ECR), sem criar nada
EXPECTED_ACCOUNT=$ACCOUNT python scripts/gold_preflight.py

# Teto do projeto: gasto bruto, consumo pendente e estimativa da próxima etapa
python scripts/cost_gate.py --spent 0.00 --pending 0.00 --estimate 0.90

# Estado de uma data e da última gold publicada
aws dynamodb get-item --table-name $TABLE --consistent-read --key '{"pk":{"S":"pipeline#2026-10-19"}}'
aws dynamodb get-item --table-name $TABLE --consistent-read --key '{"pk":{"S":"pipeline#published"}}'

# Validar a definição renderizada de um plano revisado, antes do apply (sem custo)
terraform -chdir=infra/environments/dev show -json plan.tfplan \
  | jq -r '.. | objects | select(.type? == "aws_sfn_state_machine") | .values.definition' | head -1 > /tmp/pipeline.asl.json
aws stepfunctions validate-state-machine-definition --definition file:///tmp/pipeline.asl.json
```

## Executar uma data (fase 5)

```bash
aws stepfunctions start-execution --state-machine-arn $SFN \
  --name manual-2026-10-19-$(date +%s) --input '{"reference_date":"2026-10-19"}'
aws stepfunctions describe-execution --execution-arn <arn retornado> --query '{status:status,output:output,error:error}'
```

Resultados possíveis na saída da execução:

| Resultado | Significado | Ação |
| --- | --- | --- |
| `PUBLISHED` | bronze, silver e gold concluídos; `pipeline#published` atualizado | conferir consultas gold |
| `ALREADY_PUBLISHED` | a data já estava publicada; nada pago foi executado | nenhuma |
| `SOURCE_UNAVAILABLE` | feriado ou arquivo ainda não publicado (HTTP 404 / série vazia) | repetir mais tarde se for dia de pregão |
| falha `PipelineBusy` | outra execução detém o lease | aguardar; o lease expira em 65 min se a outra foi abortada |
| falha `PipelineFailed.<etapa>` | `pipeline#<data>` registra `failed_step` e `error_type` | diagnosticar nos logs da etapa antes de repetir |

## Reprocessar

- Depois de corrigir a causa, repita a mesma entrada: bronze e silver já concluídos são reaproveitados; só as etapas pendentes rodam.
- Para reconstruir deliberadamente uma data já publicada: `--input '{"reference_date":"2026-10-19","force":true}'`. Isso repete o MERGE silver (idempotente) e o rebuild gold — tem custo.
- Nunca apagar itens do DynamoDB nem objetos bronze para "forçar" uma repetição.

## Piloto gold isolado (fase 4, antes da orquestração)

Sequência completa em [phase-4.md](phase-4.md#sequência-de-implantação-após-revisão). Após o apply com `GOLD_IMAGE_DIGEST`:

```bash
cd infra/environments/dev   # checkout com backend configurado
CLUSTER=$(terraform output -raw gold_cluster_arn)
TASKDEF=$(terraform output -raw gold_task_definition_arn)
NETWORK=$(terraform output -json gold_network_configuration)
aws ecs run-task --cluster $CLUSTER --task-definition $TASKDEF --launch-type FARGATE \
  --network-configuration "$NETWORK" --count 1 --query 'tasks[0].taskArn' --output text
aws ecs describe-tasks --cluster $CLUSTER --tasks <taskArn> --query 'tasks[0].{status:lastStatus,exit:containers[0].exitCode,reason:stoppedReason}'
aws logs tail /b3-lakehouse-aws/gold --since 1h
```

## Consultar a gold

Sempre pelo workgroup dedicado (limite de 1 GiB por consulta). As consultas de referência estão em [gold-queries.sql](gold-queries.sql).

```bash
aws athena start-query-execution --work-group b3-lakehouse-aws-gold \
  --query-string "select count(*) from b3_lakehouse_gold.fct_daily_quotes"
aws athena get-query-execution --query-execution-id <id> \
  --query 'QueryExecution.{state:Status.State,bytes:Statistics.DataScannedInBytes}'
aws athena get-query-results --query-execution-id <id>
```

## Quarentena e lacunas

- Linhas COTAHIST inválidas do histórico ficam em `quarantine.jsonl` por ano (374 no total) e não entram na silver; a bronze preserva o arquivo original. Ver [evidências do histórico](history-complete-evidence.md).
- Ausências do BCB permanecem `NULL`; a gold bloqueia comparações com CDI sem cobertura completa (`return_status`). Não preencher valores.
- `possible_corporate_event` é só uma heurística (|variação| ≥ 30%), não confirmação de evento.

## Interromper

```bash
aws stepfunctions stop-execution --execution-arn <arn> --cause "operator stop"
aws ecs list-tasks --cluster b3-lakehouse-aws-gold --desired-status RUNNING
aws ecs stop-task --cluster b3-lakehouse-aws-gold --task <taskArn> --reason "operator stop"
aws athena list-query-executions --work-group b3-lakehouse-aws-gold --max-results 20
aws athena stop-query-execution --query-execution-id <id>
```

Parar a execução do Step Functions encerra a tarefa ECS e o job Glue em andamento (integrações `.sync`), mas confira sempre se não restou tarefa, job ou consulta ativa. O lease é liberado pela própria execução ou expira em 65 minutos.

Agendamento: manter `ORCHESTRATION_SCHEDULE_ENABLED=false` (e `BRONZE_SCHEDULE_ENABLED=false`). Para desligar um agendamento aprovado, altere a variável **e** dispare `Reviewed infrastructure` na main com operação `apply` e confirmação `APPLY b3-lakehouse-aws`, revisando o plano antes de aprovar `aws-apply` — mudar a variável sozinha não dispara workflow.

## Encerramento

1. Desligar agendamento e confirmar que não há execução, tarefa, job ou consulta em andamento.
2. Registrar custo final por serviço e pela tag `Project`, com período e data da leitura.
3. Decidir retenção: buckets e ECR têm `force_destroy = false` de propósito. Exportar evidências antes de qualquer remoção autorizada; remover painel e alarmes primeiro se só eles gerarem custo fixo.
4. Desativar as flags na ordem inversa (orquestração → gold → histórico → silver → bronze) com planos revisados, preservando o estado Terraform.
