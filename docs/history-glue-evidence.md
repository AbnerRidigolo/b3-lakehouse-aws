# Carga histórica 2025 comprovada no Glue

Em 07/10/2026, após autorização da troca de EMR para Glue para preservar o plano FREE e da reserva USD 0,50, foi executada UMA chamada histórica. Nenhuma repetição anual foi realizada; não afirmar idempotência anual testada por rerun.

## Implantação e verificações prévias

PR #12 mesclado; [workflow 37708102204](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/37708102204) concluiu plan e apply com sucesso. Cinco recursos novos (job, papel runtime, política runtime e dois log groups) confirmados no estado remoto. Os três artefatos históricos existentes foram preservados, com atualizações dos scripts necessárias à alternativa.

AWS CLI confirmou Glue 5.0, dois G.1X, timeout quinze minutos, max_retries=0, max_concurrent_runs=1, nenhuma conexão VPC, parâmetros 2025/engine Glue fixos e boundary esperada. Driver e ZIP de bibliotecas recuperados do S3: SHA-256 igual ao build revisado. Bronze anual SUCCESS e inexistência de job anterior confirmados antes de iniciar. Plano FREE/ACTIVE conferido antes e depois da execução.

## Resultado real

JobRunId: `jr_bf7d7c224dca3511e41c17db3e66d7b40ef1351418df872e48f97bcb8f7ffb08`.

Glue SUCCEEDED, ExecutionTime 110 segundos, DPUSeconds 221. Leitura consistente DynamoDB confirmou history#2025 SUCCESS, b3_daily=83.722 e bcb_daily=756. manifest_sha256 coincide com bronze#year=2025. O job verifica os hashes dos 17 payloads do manifesto e compara bidirecionalmente os dados Iceberg relidos de 2025 com as entradas antes de gravar SUCCESS.

As duas tabelas continuam Iceberg v2. Metadados dos snapshots foram lidos diretamente do bucket silver:

- b3_daily: snapshot 2308411557839687557, pai 7567154637832646006; operação append, added-records=83.722, total-records=84.039, deleted-records=0 e deleted-data-files=0.
- bcb_daily: snapshot 8157393971921421870, pai 1617791231911073324; operação append, added-records=756, total-records=759, deleted-records=0 e deleted-data-files=0.

Os snapshots pais são exatamente os capturados antes da carga, com 317 cotações e 3 taxas de 01/10/2026. Contagens totais igualam dados anteriores + dados de 2025, sem remoção de registros ou arquivos antigos. Isso comprova a preservação dos registros anteriores no catálogo atual; não apenas sua permanência física como arquivos órfãos no S3.

## Custo observado e limites

Computação estimada: 221/3600 ×USD 0,44 = aproximadamente **USD 0,02701**, pela referência de tarifa [Glue](https://aws.amazon.com/glue/pricing/). DPUSeconds é informação do serviço; o cálculo não é medição final no billing e não inclui todos os custos auxiliares de S3, logs, catálogo e DynamoDB.

Budget consultado após as verificações: conta inteira USD 0,45 (última atualização 07/10/2026 17:08:05 São Paulo); filtro Project USD 0,066 (17:11:33). Ambos estão atrasados em relação à chamada histórica e não são custo final do piloto. Não deduzir custo zero ou somar essas duas leituras como se fossem gastos separados.

Nenhuma alteração de plano, assinatura paga ou Organizations. EMR continua não executado: a criação anterior falhou com SubscriptionRequiredException e foi desativada, preservando artefatos. Não houve nova tentativa EMR, segunda execução Glue histórica, backfill de outros anos, consulta Athena ou gold.

Arquivos detalhados de metadata, estado do job e observações ficam em local/, ignorados pelo Git. Evidências de integração real complementam os testes offline; não substituem validação de falha parcial ou rerun anual, que ainda não foram exercitados. Histórico completo, gold/dbt e orquestração ponta a ponta permanecem pendentes.
