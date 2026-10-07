# Estimativa: piloto silver de uma data

Preparada em 06/10/2026 e autorizada pelo proprietário antes da execução. Teto total do projeto USD 10; reservar USD 2 para limpeza e uso atrasado. Créditos Free Tier não reduzem o consumo bruto usado no planejamento.

Escopo: bootstrap IAM, implantação de bucket/scripts/catalog database/logs/job, uma execução Glue incremental para 01/10/2026 e uma repetição da mesma data para validar MERGE. Sem histórico, Athena, EMR, otimização automática de Iceberg, crawler, sessão interativa ou agendamento.

[AWS Glue pricing](https://aws.amazon.com/glue/pricing/) informa USD 0,44 por DPU-hora no exemplo de ETL; confirmar a tarifa de us-east-1 no momento de autorizar. [G.1X](https://docs.aws.amazon.com/glue/latest/dg/add-job.html) equivale a uma DPU por worker. Planejamento: 2 workers × 10/60 h × USD 0,44 = USD 0,1467 por execução; duas execuções = USD 0,2934 de processamento.

Reserva proposta para o conjunto: **USD 0,50**, cobrindo estimativa de processamento e margem para inicialização/faturamento, S3, logs, catálogo e DynamoDB. Previsão de volume muito pequena (317 cotações + 3 taxas); considerar até 10 MiB de dados/metadata/temp e 10 MiB de logs no piloto. Reavaliar se logs/duração/armazenamento ultrapassarem as premissas. Não executar terceira tentativa dentro de autorização para duas chamadas: investigar primeiro e pedir novo orçamento quando necessário.

Timeout e budget não são limites absolutos de cobrança. Custos reais dependem da duração faturada, tarifação e atraso do billing. AWS não cobra computação Spark por manter apenas a definição do job; armazenamento/logs continuam tendo custo. Não deixar nenhum compute fixo.

Última leitura conhecida: USD 0,335 da conta inteira, atualização em 06/10/2026 20:19:32 São Paulo. Não é custo final isolado deste projeto. Reservar adicionalmente USD 0,20 para consumo bronze ainda não refletido, de forma conservadora.

Verificação offline proposta: `python scripts/cost_gate.py --spent 0.335 --pending 0.20 --estimate 0.50`. Com reserva fixa de USD 2, saldo de planejamento USD 6,965. Essa verificação não autoriza operação e não impõe teto na AWS.

Depois das chamadas, registrar JobRunId, status, duração, DPUSeconds quando disponível, consumo por tag/serviço e período da medição. Só iniciar histórico após estimativa separada e aprovação.

Piloto concluído: duas chamadas SUCCEEDED, 525 DPU-segundos totais; computação estimada USD 0,06417 pela tarifa de referência. Contagens mantidas na repetição. [IDs, snapshots, verificações e leitura atrasada dos budgets](../silver-data-evidence.md). Custo final por serviço ainda não disponível; essa estimativa não substitui billing.
