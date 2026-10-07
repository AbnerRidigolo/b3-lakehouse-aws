# Silver incremental: evidências reais

Piloto autorizado dentro da reserva de USD 0,50, para a data 01/10/2026, com uma carga e uma repetição. Não inclui histórico ou EMR.

## Implantação

- Bootstrap aplicado: boundary silver e duas políticas CI; três criações, zero alterações, zero exclusões.
- PR #9 mesclado. [Workflow 37555576785](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/37555576785) concluiu plan e apply com sucesso.
- Treze recursos silver registrados no estado remoto Terraform. Bronze preservada.
- Glue 5.0, dois workers G.1X, timeout dez minutos, zero retentativas automáticas, uma execução simultânea e nenhuma conexão VPC.
- Scripts S3 recuperados e SHA-256 comparados com o build revisado: ambos iguais. Boundary do papel Glue e bloqueio de acesso público do bucket conferidos.
- IAM Simulator confirmou leituras CI verificadas, criação do job pelo apply e negação de StartJobRun para o CI. Atualização DynamoDB de chave silver pelo runtime permitida.

## Primeira execução

JobRunId: `jr_96c201f5eaa2cdf56012b870cf392cddb9dbe60e76b95788df87d781e6771c8f`.

Glue SUCCEEDED; ExecutionTime 123 segundos; DPUSeconds 246. DynamoDB `silver#2026-10-01` SUCCESS, com 317 registros b3_daily e 3 bcb_daily. O job compara bidirecionalmente o conteúdo relido do Iceberg com as entradas validadas antes de gravar SUCCESS.

GetTable confirmou as duas tabelas ICEBERG no database b3_lakehouse_silver. Metadata JSON lido diretamente do bucket silver confirmou format-version=2 e total-records:

- b3_daily: 317; snapshot inicial 682400902156638484.
- bcb_daily: 3; snapshot inicial 2360505597724024553.

Hashes das entradas bronze foram conferidos pelo job antes do processamento. A ingestão bronze não foi repetida neste piloto.

## Repetição

Segunda chamada com a mesma data: `jr_bfb0f97c6556477d9037a10a78967dcb7090e56a4f99934683fc888215660d2f`. Glue SUCCEEDED, ExecutionTime 139 segundos, DPUSeconds 279. DynamoDB permaneceu SUCCESS com as mesmas contagens, e todos os hashes da silver coincidiram com as quatro origens bronze.

Metadados dos novos snapshots relidos do S3 confirmaram:

- b3_daily: 317 registros; snapshot 7567154637832646006.
- bcb_daily: 3 registros; snapshot 1617791231911073324.

O MERGE foi executado novamente, criou snapshots e manteve as contagens. O read-back bidirecional no job também passou; não houve duplicação de chaves ou divergência de conteúdo. Não interpretar idempotência como ausência de novas gravações/arquivos Iceberg.

## Custo e limites

Total informado pelo Glue: 525 DPU-segundos. Computação estimada: 525/3600 × USD 0,44 = aproximadamente USD 0,06417, usando a referência de tarifa registrada na [estimativa](costs/silver.md). Isso não é o custo medido no billing; S3, logs, catálogo, DynamoDB e possível uso faturável adicional são separados.

Consulta aos budgets após as duas chamadas: conta inteira USD 0,335, atualização em 06/10/2026 às 20:19:32 São Paulo; filtro por projeto USD 0,00, atualização 20:16:00. Ambos permanecem atrasados e não comprovam custo final nem projeto gratuito. A reserva aprovada era USD 0,50; nenhuma terceira chamada foi realizada.

Os arquivos de dados e metadados detalhados ficam em local/ e não são versionados. Athena não foi usado; gold, Step Functions ponta a ponta e EMR/histórico continuam pendentes. As duas tabelas têm commits separados; a validação do piloto não simula falha parcial entre eles.
