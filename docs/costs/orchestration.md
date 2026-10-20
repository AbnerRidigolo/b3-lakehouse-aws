# Estimativa da fase 5 — orquestração (não autorizada ainda)

Preparada em 20/10/2026. Região us-east-1, plano FREE preservado, consumo bruto sem descontar créditos. Pressupõe a gold da fase 4 já implantada e validada; não repete os custos daquela fase.

Escopo: bootstrap IAM, implantação de Step Functions, SNS, SQS, regra EventBridge, dois alarmes, um painel e um scheduler **DISABLED**; quatro execuções-piloto ([phase-5.md](../phase-5.md)), das quais só a primeira roda Glue e Fargate. Sem agendamento recorrente.

| Item | Hipótese conservadora | Reserva |
| --- | --- | --- |
| Glue silver | 1 execução, 2 G.1X × 10 min × USD 0,44/DPU-h (o piloto silver mediu bem menos) | USD 0,15 |
| Fargate gold | 1 tarefa 0,5 vCPU/1 GiB ≤ 30 min + IPv4 público | USD 0,05 |
| Athena gold | Rebuild completo; usar os bytes medidos no piloto da fase 4 e revisar se passar de 10 GB | USD 0,10 |
| Step Functions, Lambda, DynamoDB, SNS, SQS, EventBridge | ~25 transições por execução, poucos e-mails e mensagens | USD 0,02 |
| Alarmes CloudWatch | 2 alarmes por um mês (USD 0,10 cada, sem considerar o nível gratuito) | USD 0,20 |
| Painel CloudWatch | USD 3/mês bruto se o nível sempre gratuito (3 painéis) não cobrir; manter no máximo 3 dias para a evidência ou confirmar a cobertura na fatura | USD 0,30 |
| Margem | Arredondamento e atraso de faturamento | USD 0,08 |
| **Total** | | **USD 0,90** |

Antes do apply: `python scripts/cost_gate.py --spent <gasto bruto atual> --pending <pendente> --estimate 0.90`, com a reserva fixa de USD 2. A estimativa não é aprovação, e budgets não bloqueiam gasto.

**Recorrência não está incluída.** Um dia útil agendado custa da ordem de USD 0,15 a 0,30 (Glue + Fargate + Athena), ou seja, USD 3 a 6 por mês — incompatível com o teto total de USD 10 se ficar ligado indefinidamente. Qualquer agendamento precisa de horizonte definido (ex.: uma semana para evidência), estimativa própria e plano de desligamento.

Fontes de preço: [Step Functions](https://aws.amazon.com/step-functions/pricing/), [CloudWatch](https://aws.amazon.com/cloudwatch/pricing/), [SNS](https://aws.amazon.com/sns/pricing/), [SQS](https://aws.amazon.com/sqs/pricing/), [Glue](https://aws.amazon.com/glue/pricing/), [Fargate](https://aws.amazon.com/fargate/pricing/), [Athena](https://aws.amazon.com/athena/pricing/). Confirmar as tarifas antes de autorizar.
