# Orquestração — evidências dos pilotos na AWS

Execuções em 22/10/2026 (UTC), us-east-1, com aprovação do proprietário (reserva de USD 0,90, [estimativa](costs/orchestration.md)). Leituras pelas APIs de controle da AWS e logs do GitHub Actions; o ID da conta é omitido. Agendamento permanece **DISABLED**.

## Implantação

| Etapa | Resultado |
| --- | --- |
| Verificação prévia sem custo | 47 chamadas do Terraform simuladas contra a policy de CI ainda não aplicada (`iam:SimulateCustomPolicy`) e conferidas no código do provider 6.66.0: `states:ValidateStateMachineDefinition` (chamada no **plan**), `sns:GetSubscriptionAttributes`, `Unsubscribe` e `SetSubscriptionAttributes` não aceitam permissão por recurso. 18 chamadas de runtime da máquina de estados simuladas conforme esperado, incluindo negações. Definição renderizada validada com `ValidateStateMachineDefinition`: `OK`, sem diagnósticos |
| Bootstrap (PR #21, aplicado pelo proprietário) | `6 to add, 2 to change, 0 to destroy`: boundaries `pipeline-sfn` e `pipeline-scheduler`, policies `pipeline-ci-plan/apply` e `ListInstanceProfilesForRole` nas policies gold |
| Variável e gatilho (PR #22) | O primeiro run leu `ENABLE_ORCHESTRATION=false` e não teve mudanças; o workflow ganhou `workflow_dispatch` com operação `apply` (só na main, confirmação `APPLY b3-lakehouse-aws`, aprovação `aws-apply`) |
| Apply do merge do PR #22 ([run 39531642715](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/39531642715)) | 16 dos 17 recursos criados; `SetTopicAttributes` rejeitou a policy do tópico SNS: `Every policy statement must have a unique ID` |
| Correção (PR #23, [run 39703217988](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/39703217988)) | `Sid` único por statement e teste no módulo; `1 to add, 0 to change, 0 to destroy` |

Estado conferido após o apply: máquina de estados `b3-lakehouse-aws-pipeline` ACTIVE (STANDARD, task definition `b3-lakehouse-aws-gold:2`), assinatura de e-mail confirmada (1 confirmada, 0 pendente), regra EventBridge ENABLED com 1 target, alarmes de DLQ e erros da Lambda, painel `b3-lakehouse-aws-pipeline`, schedule DISABLED.

## Pilotos

| Piloto | Entrada | Resultado | Caminho | Duração |
| --- | --- | --- | --- | --- |
| 1. Sucesso | `{"reference_date": "2026-10-20"}` | SUCCEEDED, `PUBLISHED` | AcquireLock → Bronze → MarkRunning → Silver (Glue `.sync`) → Gold (ECS `.sync`) → MarkSuccess → PublishMarker → ReleaseLock | 7 min 08 s (01:09:29–01:16:37) |
| 2. Repetição | mesma data | SUCCEEDED, `ALREADY_PUBLISHED` | AcquireLock → Bronze → ReadPipelineStatus → SkipPublished → ReleaseLock | 2,4 s |
| 3. Feriado | `2026-10-12` | SUCCEEDED, `SOURCE_UNAVAILABLE` | AcquireLock → Bronze (`SourceNotAvailable`) → SourceUnavailable → ReleaseLock | segundos |
| 4. Falha controlada | `2099-01-02` | FAILED, `PipelineFailed.bronze` (`ValueError`) | AcquireLock → Bronze → HandleFailure → MarkFailed → ReleaseLockAfterFailure → PipelineFailed | segundos |

Piloto 1 em detalhe:

- Bronze: `bronze#2026-10-20` SUCCESS em ~5 s.
- Silver: Glue `b3-lakehouse-aws-silver` SUCCEEDED, 110 s, 2 × G.1X, 220 DPU-segundos; `silver#2026-10-20` SUCCESS com 325 cotações e 3 taxas e os SHA-256 das fontes.
- Gold: tarefa `2137b7b41e9e420e82742750ad99cfe7` (`b3-lakehouse-aws-gold:2`), criada 01:12:29, parada 01:16:35, exit code 0; `dbt build` PASS=25 WARN=0 ERROR=0; `mart_daily` passou de 3.185.477 para 3.185.802 linhas (+325).
- Controle: `pipeline#2026-10-20` SUCCESS com o ARN da tarefa; `pipeline#published` = 2026-10-20; lease liberado.

Repetição sem duplicação: o piloto 2 não iniciou Glue nem Fargate (um único job Glue e uma única tarefa para a data). Feriado: nenhum item `silver#` ou `pipeline#` criado para 2026-10-12; a bronze ficou `FAILED/SourceNotAvailable`, podendo ser repetida. Falha: `pipeline#2099-01-02` FAILED com `failed_step=bronze`; `pipeline#published` permaneceu em 2026-10-20 (não retrocede).

## Alerta e DLQ

Para a falha do piloto 4, nos 30 minutos seguintes: regra EventBridge com 1 evento casado, 1 invocação e 0 falhas; SNS com 1 mensagem publicada, 1 entregue e 0 falhas; DLQ com 0 mensagens. A DLQ não foi exercitada porque a entrega funcionou.

## Achados

- **Feriado dispara o alarme de erros da Lambda.** `SourceNotAvailable` é levantada como exceção, então conta na métrica `Errors` da Lambda: os pilotos 3 e 4 somaram 2 erros e o alarme `b3-lakehouse-aws-pipeline-bronze-errors` foi para ALARM às 01:19:18. Com o agendamento ativo, todo feriado geraria alerta falso. Correção possível, não implementada: alarmar sobre falhas da máquina de estados (já cobertas pela regra EventBridge) ou sobre um filtro de log que exclua `SourceNotAvailable`.
- **CDI e Selic com o mesmo hash em 2026-10-20.** Não é erro de ingestão: as séries SGS 12 e 11 diferem em 2010 (ex.: 0,032780 × 0,032927 em 01/03/2010) e publicaram a mesma taxa diária nas datas recentes consultadas (2024–2026).
- **Não demonstrado na AWS:** a retomada após falha da gold sem repetir a silver (`silver#` SUCCESS → direto para a gold) e o lease ocupado/expirado continuam cobertos apenas pela simulação offline (`tests/test_orchestration.py`).
- Entre 01/10 e 20/10/2026 há dias úteis não carregados; 2026 permanece incompleto.

## Custo

Estimativas a partir do consumo observado (a fatura ainda não reflete os pilotos).

| Item | Estimativa |
| --- | --- |
| Glue silver (220 DPU-s × USD 0,44/DPU-h) | ~ USD 0,027 |
| Fargate 0,5 vCPU/1 GiB e IPv4 por ~4 min | ~ USD 0,002 |
| Athena (46 consultas do build, 413 MB) | ≤ USD 0,003 |
| Step Functions, Lambda, DynamoDB, SNS, EventBridge | dentro do nível gratuito |
| 2 alarmes CloudWatch | ~ USD 0,20/mês enquanto existirem |
| Painel CloudWatch | USD 0 se coberto pelos 3 painéis gratuitos; até USD 3/mês caso contrário |

Budget da conta (sem créditos) lido em 22/10 antes dos pilotos: USD 2,725 (atualizado em 21/10 12:16 UTC); tag Project USD 1,633. Ao final, nenhuma execução, tarefa ou consulta em andamento.
