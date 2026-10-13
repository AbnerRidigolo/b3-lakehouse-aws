# Fase 4 — gold preparada para revisão

Estado em 12/10/2026: código integrado na main pelo PR #15, CI e build Linux da imagem aprovados. A gold ainda não foi implantada nem executada no Athena/Fargate. Consulte o [plano de continuidade](CONTINUIDADE.md) antes de operar. O histórico real da silver está documentado em [evidências consolidadas](history-complete-evidence.md).

## Modelos

| Modelo | Grão e finalidade |
| --- | --- |
| dim_asset | Uma versão observada dos atributos ticker, ISIN, empresa e especificação. A chave preserva a identidade histórica; não assume ticker estável ao longo das décadas. |
| dim_calendar | Uma data civil entre a primeira e a última cotação disponível. Distingue dia da semana de pregão observado; não é um calendário oficial de feriados da bolsa. |
| dim_rates | Uma data com CDI/Selic em percentual diário e câmbio na unidade original. Ausências permanecem NULL. |
| fct_daily_quotes | Um ticker/data, com OHLC original, preços por unidade, moeda, fator, distribuição, negócios, quantidade e volume. |
| mart_daily | Variação de preço não ajustada, classificação de comparabilidade, CDI do intervalo, excesso relativo, volatilidade e liquidez. |
| mart_monthly | Composição mensal somente com cobertura completa segundo os pregões observados; mês parcial e períodos inválidos permanecem sem retorno. |

Preços por unidade dividem o valor original pelo fator de cotação. Mudança de moeda, atributos do ativo, fator ou distribuição bloqueia o retorno comparável. Variações absolutas de pelo menos 30% são sinalizadas como possíveis eventos corporativos; essa heurística não confirma eventos nem detecta todos os ajustes. Os resultados nunca representam retorno total ajustado por proventos.

O retorno diário exige observações em pregões observados consecutivos e intervalo de até sete dias corridos. CDI é composto no intervalo `(cotação anterior, cotação atual]`, incluindo observações BCB existentes em dias sem cotação B3. Qualquer CDI ausente em pregão observado bloqueia a comparação. A cobertura não certifica dias bancários ausentes simultaneamente nas duas fontes; não há calendário bancário oficial incorporado.

O excesso relativo é `(1 + retorno_preço) / (1 + retorno_CDI) - 1`. Volatilidade usa desvio padrão amostral de 21 retornos válidos, anualizado por raiz de 252; trata-se de convenção, não contagem histórica de pregões. Liquidez é volume médio em 21 observações consecutivas na mesma moeda, dentro de 45 dias. Não mistura moedas nem converte valores históricos para reais atuais.

## Contratos e publicação

O contêiner executa testes de origem antes de escrever gold, depois `dbt build --fail-fast`. Testes conferem unicidade, OHLC, unidades das taxas, chaves das dimensões, reconciliação de contagens e supressão de retornos inválidos. A validação do rodapé original continua na bronze/silver.

O build não é uma transação atômica de todo o catálogo: uma falha posterior pode deixar modelos parcialmente atualizados. Consumidores só devem considerar a execução publicada quando todos os testes terminarem com sucesso. Na fase 5, o status do pipeline será a barreira de publicação. Não executar dois builds simultaneamente.

Para o volume atual, os seis modelos são reconstruídos integralmente e sem partições. Isso evita o limite de 100 partições de escrita do CTAS ao tratar 40 anos. O piloto deve medir bytes lidos e duração antes de autorizar uso recorrente. Não há rotina de limpeza automática de snapshots/dados gold.

## Infraestrutura preparada

Terraform inclui bucket privado com TLS e SSE-S3, expiração somente dos resultados Athena, workgroup engine 3 com limite de 1 GiB por consulta, catálogo gold, ECR com tags imutáveis, cluster ECS sem serviço permanente, tarefa de 0,5 vCPU/1 GiB, logs de três dias, VPC/sub-rede pública e acesso HTTPS de saída. Não há NAT Gateway, EC2, balanceador ou IP elástico.

Os papéis de tarefa e execução têm boundaries separados. A tarefa lê silver, escreve apenas gold/resultados e usa exclusivamente o workgroup dedicado. CI pode implantar infraestrutura e publicar a imagem, mas não recebe RunTask nem StartQueryExecution. `enable_gold=false` por padrão. Sem digest revisado não existe task definition.

O processo dbt tem prazo de 20 minutos. Esse prazo não inclui pull/provisionamento do ECS e não garante cancelamento de consultas Athena já enviadas. O piloto precisa acompanhar a tarefa e verificar/cancelar consultas remanescentes em falha ou timeout. Step Functions acrescentará o limite externo na fase 5.

## Sequência de implantação após revisão

1. Concluído: commits publicados com autorização e integrados pelo proprietário no PR #15; CI e build Linux passaram. Para novas alterações, manter aprovação por commit e PR/merge pelo proprietário.
2. No CloudShell autenticado, executar `python scripts/gold_preflight.py` no checkout revisado. Conferir plano FREE, budgets atualizados e existência de AWSServiceRoleForECS. Essa leitura não comprova elegibilidade de Fargate nem substitui o primeiro piloto.
3. Conferir o teto total com `scripts/cost_gate.py`, incluindo consumo ainda não faturado e reserva de USD 2. Aprovar a [estimativa](costs/gold.md) antes de qualquer apply/publicação/execução.
4. Revisar e aplicar bootstrap com `enable_gold_permissions=true`. Criar o service-linked role somente se estiver ausente, usando `create_ecs_service_role=true`; preservar configurações anteriores.
5. Habilitar `ENABLE_GOLD=true`, inicialmente sem `GOLD_IMAGE_DIGEST`. Revisar/aplicar o plano de infraestrutura pelo fluxo existente.
6. Disparar manualmente `Reviewed gold image publication` em main, com a confirmação indicada. O workflow constrói, publica no ECR e informa o digest; não executa a tarefa.
7. Revisar o digest, definir `GOLD_IMAGE_DIGEST` e executar um novo plan/apply. O workflow atual só aplica em push de main; workflow_dispatch com operação plan produz apenas plano. Usar uma mudança revisada em main ou aplicação explícita do plano pelo operador, sem supor que o dispatch aplicou.
8. Executar uma única tarefa Fargate com a configuração de rede exportada pelo Terraform, após aprovação de custo. Parar em falha, sem rerun automático. Conferir exit code, resultados dbt, contagens e amostras usando [consultas](gold-queries.sql), e registrar bytes e duração.

## Verificação local e limites

48 testes e 24 subtestes Python passaram; modelos reais são renderizados e executados com dados sintéticos em DuckDB, após tradução de Trino pelo SQLGlot. `dbt parse` passou com dbt-core 1.12.5 e dbt-athena 1.11.1. Testes Terraform usam provider simulado. Nenhum desses testes comprova uma execução real de Athena/Iceberg.

Docker Desktop não disponibilizou o engine Linux local. O build Linux passou no CI 38327864068; a imagem ainda não foi publicada no ECR e será reconstruída no workflow de publicação. Dependências diretas dbt/adaptador estão fixadas; dependências transitivas e a imagem base ainda podem mudar entre builds. A implantação usa o digest da imagem construída, não uma tag mutável.

Referências: [configuração oficial dbt-Athena](https://docs.getdbt.com/docs/local/connect-data-platform/athena-setup), [configurações Iceberg e partições](https://docs.getdbt.com/reference/resource-configs/athena-configs).
