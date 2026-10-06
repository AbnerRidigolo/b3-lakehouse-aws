# Estimativa inicial da fase 2

Estimativa de planejamento em 06/10/2026; não é custo observado nem autorização de implantação. Região us-east-1. Teto total do projeto USD 10, incluindo fases futuras; preservar USD 2 de reserva.

Proposta: reservar até USD 0,20 para preparar permissões/estado, criar a infraestrutura, duas invocações manuais para uma data (carga + idempotência), logs curtos e retenção dos quatro objetos por 30 dias. Scheduler ficará desativado. Não considera backfill, Glue, EMR, Athena, ECS, ECR ou Redshift.

Hipóteses conservadoras: Lambda 512 MB, máximo 180 s por chamada (duas chamadas totalizam 180 GB-s); uma referência de planejamento de USD 0,00002 por GB-s dá USD 0,0036 de compute, antes de benefícios. Até 128 MiB de objetos brutos (limites máximos dos quatro downloads), menos de 1 MiB de logs, poucas dezenas de operações S3/DynamoDB e objetos de estado/versionamento. A reserva USD 0,20 é margem para requisições e pequenas variações, sem depender dos créditos Free Tier. O ZIP B3 verificado manualmente tinha cerca de 0,46 MB; o limite de 128 MiB é conservador, não volume medido da carga AWS.

Fontes de precificação consultadas: https://aws.amazon.com/lambda/pricing/ , https://aws.amazon.com/s3/pricing/ , https://aws.amazon.com/dynamodb/pricing/ , https://aws.amazon.com/eventbridge/pricing/ . A taxa de compute acima é uma hipótese arredondada para o cálculo, não uma cotação exata. Antes do apply, confirmar preços e plano gerado.

Último consumo registrado foi USD 0,047 no budget de toda a conta em 01/10/2026. Esse valor está desatualizado em 06/10/2026 e pode incluir outros projetos. Atualizar budgets antes de aprovar execução; somar consumo já medido e uso pendente estimado. Não preencher pendente=0 sem verificar o atraso de faturamento.

Essa reserva não habilita o agendamento diário. Ele exige estimativa separada (incluindo falhas/retentativas e retenção crescente) e aprovação. Controlar o término da conta Free Tier; não habilitar Organizations ou Identity Center como parte desta fase.
