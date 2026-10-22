# Encerramento — fase 6

Preparado em 22/10/2026. Separa o que está decidido, o que depende do proprietário e a sequência de desligamento. Nenhuma remoção foi executada.

## Prazo que governa a retenção

O plano da conta é **FREE**, com expiração em **02/12/2026** (`GetAccountPlanState`). Segundo a [documentação da AWS](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html), quando o plano expira a conta é suspensa, recursos e dados ficam inacessíveis e tudo é apagado após 90 dias, salvo conversão para o plano pago — que o projeto não faz sem decisão explícita do proprietário. Portanto, **tudo que precisa sobreviver deve estar no repositório ou em prints antes de 02/12/2026**: evidências, consultas, custo final e capturas de tela.

## Estado implantado (22/10/2026)

| Recurso | Custo recorrente esperado |
| --- | --- |
| S3: bronze 1,42 GB, silver 0,10 GB, gold (pequeno), estado 3 MB | ~ USD 0,04/mês |
| ECR: 1 imagem de 152,8 MB | ~ USD 0,015/mês |
| 2 alarmes CloudWatch e 1 painel | dentro do nível sempre gratuito (10 alarmes, 3 painéis), a confirmar na fatura |
| Lambda, Glue job, Step Functions, DynamoDB, SNS, SQS, EventBridge, ECS cluster, VPC sem NAT | sem custo parado; cobram só ao executar |
| Scheduler do pipeline e do bronze | **DISABLED** |

Budget da conta (sem créditos) em 21/10 12:16 UTC: USD 2,725 de USD 10; previsão até 01/12: USD 4,886. O custo final por serviço deve ser lido depois do atraso de faturamento dos pilotos de 21–22/10.

## Decisões do proprietário

**Decidido em 22/10/2026:** agendamento **desligado** e conta mantida como está até **expirar em 02/12/2026**, sem desligamento antecipado. Até lá, concluir prints, post e a leitura do custo final.

1. **Agendamento:** manter desligado (recomendado). Ligar custa ~USD 0,15–0,30 por dia útil e, antes disso, o alarme de erros da Lambda precisa parar de disparar em feriados ([achado](orchestration-evidence.md#achados)). Qualquer ativação exige horizonte, estimativa e data de desligamento.
2. **Retenção até a publicação:** manter tudo implantado até concluir prints e post (custo estimado < USD 0,10/mês).
3. **Depois da publicação:** (a) deixar a conta expirar em 02/12/2026, ou (b) desligar antes pela sequência abaixo. Em ambos os casos os dados na AWS deixam de existir; o repositório guarda código e evidências.

## Roteiro de prints (sem segredos)

Antes de capturar, oculte ID da conta, e-mail, ARNs completos e nomes de bucket com ID.

- [ ] Step Functions: grafo da execução `pilot1-2026-10-20` (todos os estados verdes) e da `pilot4-failure-2099-01-02` (caminho de falha).
- [ ] Athena (workgroup `b3-lakehouse-aws-gold`): uma consulta de [gold-queries.sql](gold-queries.sql) com resultado e bytes lidos.
- [ ] Glue Data Catalog: tabelas Iceberg silver e gold.
- [ ] ECS: tarefa gold parada com exit code 0.
- [ ] CloudWatch: painel `b3-lakehouse-aws-pipeline`.
- [ ] E-mail de alerta da falha controlada (sem cabeçalhos com o endereço).
- [ ] GitHub Actions: run com plan revisado e aprovação `aws-apply`.
- [ ] Billing/Budgets: gasto bruto final, sem créditos.

## Sequência de desligamento (se escolhida a opção b)

Cada passo é um plano revisado e aprovado; nunca usar `force_destroy` para contornar proteção de dados.

1. Confirmar que não há execução, tarefa, job Glue ou consulta Athena em andamento.
2. Registrar o custo final por serviço e pela tag `Project`, com período e data da leitura.
3. `ENABLE_ORCHESTRATION=false` → `apply` manual (remove máquina de estados, alertas, painel, scheduler).
4. `ENABLE_GOLD=false` e `GOLD_IMAGE_DIGEST` vazio → `apply`. Buckets e ECR têm `force_destroy = false`: esvaziar o bucket gold e remover a imagem é um ato explícito e separado.
5. Histórico → silver → bronze, na ordem inversa da criação, com o mesmo cuidado para buckets de dados.
6. Bootstrap por último, no CloudShell, preservando o bucket de estado até o fim.
