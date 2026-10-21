# Gold — evidências do primeiro piloto na AWS

Execução em 21/10/2026 (UTC), us-east-1, com aprovação do proprietário para publicar a imagem, implantar a infraestrutura e executar **uma** tarefa (reserva de USD 1, [estimativa](costs/gold.md)). Leituras feitas pelas APIs de controle da AWS e pelos logs do GitHub Actions; o ID da conta é omitido.

## Implantação

| Etapa | Resultado |
| --- | --- |
| Apply do merge do PR #18 ([run 39500553229](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/39500553229)) | Parcial: 17 dos 21 recursos gold criados e Lambda bronze/`silver-libs.zip` atualizados; falhou com `UnauthorizedOperation` em `CreateSubnet`, `CreateRouteTable` e `CreateSecurityGroup` sobre a VPC pai |
| Correção 1 (PR #19, bootstrap aplicado pelo proprietário: `0 to add, 1 to change, 0 to destroy`) | Statement que autoriza essas criações sobre `vpc/*` somente com a tag `Project` |
| Imagem ([gold-image.yml #1](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/39523516682)) | Tag `987aece4fded8c92402f5381679ac952d848e89f`, digest `sha256:d357906c05fa76a7814c4041d9f3f2f6cc30066cf0a6378cc5fb0e967c54fbac`, 152,8 MB comprimidos |
| Apply do merge do PR #19 ([run 39525086863](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/39525086863)) | Criou sub-rede, route table/associação, security group e `b3-lakehouse-aws-gold:1`; falhou ao ler a task definition |
| Correção 2 (PR #20, bootstrap: `0 to add, 2 to change, 0 to destroy`) | `ecs:DescribeTaskDefinition` (plan/apply) e `ecs:DeregisterTaskDefinition` (apply) em `Resource = "*"`: essas ações não aceitam permissão por recurso, confirmado com `iam:SimulatePrincipalPolicy` |
| Apply do merge do PR #20 ([run 39526664377](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/39526664377)) | `1 added, 0 changed, 1 destroyed`: `:1` desregistrada (INACTIVE) e `:2` idêntica (ACTIVE); outputs `gold_cluster_arn`, `gold_task_definition_arn` e `gold_network_configuration` disponíveis |

Rede: VPC `10.83.0.0/24`, sub-rede pública `10.83.0.0/26` (us-east-1b, sem IP automático), rota `0.0.0.0/0` para internet gateway, security group sem ingress e com egress apenas TCP 443. Sem NAT Gateway, EIP ou serviço ECS.

## Execução

A tarefa usou a revisão `:1`, já ativa e idêntica à revisão planejada, enquanto a correção 2 era preparada; a `:2` que a substituiu tem a mesma imagem, recursos, roles e variáveis.

| Item | Valor |
| --- | --- |
| Tarefa | `5bc762f7ef5c4132ac44679ed01e8c8d`, cluster `b3-lakehouse-aws-gold`, Fargate 0,5 vCPU / 1 GiB, IP público só durante a tarefa |
| Horários (UTC) | criada 01:13:17; pull 01:13:27–01:13:35; em execução 01:13:36; parada 01:16:51 |
| Saída | exit code **0**, `EssentialContainerExited` |
| Contratos de origem (`tag:source_contract`) | **PASS=3**: `source_nonempty`, `source_quotes_contract`, `source_rates_contract` |
| `dbt build --fail-fast` | **PASS=25 WARN=0 ERROR=0 SKIP=0**: 6 modelos e 19 testes em 132 s |

| Modelo | Linhas |
| --- | ---: |
| `dim_rates` | 10.030 |
| `dim_asset` | 23.124 |
| `dim_calendar` | 14.883 |
| `fct_daily_quotes` | 3.185.477 |
| `mart_daily` | 3.185.477 |
| `mart_monthly` | 259.976 |

As seis tabelas são Iceberg no catálogo `b3_lakehouse_gold`, em `s3://b3-lakehouse-aws-gold-<ACCOUNT_ID>/gold/`, consultáveis no workgroup `b3-lakehouse-aws-gold` (limite de 1 GiB por consulta).

## Consultas de aceite

Executadas no workgroup gold após o build. Bytes lidos informados pelo Athena.

| Consulta | Resultado | Bytes |
| --- | --- | ---: |
| Contagem do fato ([gold-queries.sql](gold-queries.sql) #1) | 3.185.477 | 0 (metadados) |
| Reconciliação silver × gold | silver `b3_daily` 3.185.477 = `fct_daily_quotes` 3.185.477 = `mart_daily` 3.185.477; silver `bcb_daily` 29.917 | 0 (metadados) |
| `return_status` (#2) | `unadjusted_price_return` 2.650.578; `quotation_gap` 414.306; `asset_attributes_changed` 76.385; `possible_corporate_event` 34.987; `first_observation` 5.368; `currency_change` 3.853 | 509.494 |
| PETR4 mensal 2025 (#3) | 3 meses com cobertura completa: fev (−4,67% vs CDI 0,99%), jul (+4,02% vs 1,28%), out (−5,44% vs 1,28%); demais meses sem retorno por cobertura incompleta | 2.135.453 |
| Eventos suspeitos 2025 (#4) | 50 primeiros registros (ex.: RNEW3 −77,7% em 14/02, CCTY3 +129,9% em 05/05) | 23.862.736 |
| Moedas históricas | `CR$` 1986-01-02–1994-06-30 (298.037); `CZ$` 1986-03-04–1989-01-13 (269.477); `NCZ$` 1989-01-18–1990-03-13 (106.944); `R$` 1994-07-04–2026-10-01 (2.511.019) | 901.592 |
| Lacunas BCB (`dim_rates`) | 10.030 dias; CDI em 9.966 (**64 ausentes**, mantidos `NULL`); Selic em 9.924; dólar em 10.027 | 179.687 |
| Unidade do dólar | `current_currency/USD` 1986-01-02–1994-06-30 (2.118 dias); `BRL/USD` 1994-07-01–2026-10-01 (7.909 dias) | 41.703 |

Quarentena na origem: as 374 linhas inválidas não chegaram à silver; a igualdade silver = fato = mart diário mostra que a gold não reintroduziu nem perdeu linhas.

## Achados e limitações

- **Código `CR$` ambíguo:** a fonte usa `CR$` em 1986 (antes do cruzado) e de 1990 a 1994 (cruzeiro e cruzeiro real), com `CZ$`/`NCZ$` entre eles. A gold preserva a moeda da fonte; mudanças entre cruzeiro e cruzeiro real que mantêm o mesmo código não aparecem como `currency_change` e dependem das demais regras de `return_status`.
- **Marcadores de evento na especificação:** o campo de especificação do COTAHIST recebe marcadores como `ATZ`, `EDR` e `EDJ`. Cada entrada e saída desse estado muda o `asset_key` e classifica o dia como `asset_attributes_changed`. Em PETR4/2025 isso ocorreu em 9 dos 12 meses e impediu a comparação mensal com o CDI. O comportamento é conservador (não calcula retorno sem preço ajustado), mas bloqueia também o dia de saída do marcador; normalizar esses marcadores na chave é uma melhoria possível, ainda não implementada.
- `possible_corporate_event` continua sendo heurística (variação ≥ 30% ou mudança de fator/distribuição), não confirmação de evento.
- O build não é atômico entre tabelas; nesta execução todos os modelos e testes passaram.

## Custo

Estimativas a partir do consumo observado; a fatura ainda não refletia o piloto na leitura abaixo.

| Item | Estimativa |
| --- | --- |
| Athena (45 consultas, 445,7 MB lidos; até 595,6 MB com o mínimo de 10 MB por consulta) | ≤ USD 0,003 |
| Fargate 0,5 vCPU/1 GiB e IPv4 público por ~3,5 min | ~ USD 0,002 |
| ECR (152,8 MB) | ~ USD 0,015/mês |
| S3 gold e logs (3 dias) | volume pequeno, a conciliar |

Budget da conta (sem créditos) em 20/10 22:37 UTC, antes do piloto: gasto real USD 2,68; tag Project USD 1,622. Ao final não restavam tarefas ECS nem consultas em execução. Dados gold e imagem permanecem armazenados até decisão de retenção.
