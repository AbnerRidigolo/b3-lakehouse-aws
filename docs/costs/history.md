# Estimativa: um backfill EMR de 2025

Preparada em 07/10/2026; ainda não autorizada. Teto total do projeto USD 10, com USD 2 reservados. Créditos não reduzem o consumo bruto do planejamento.

Escopo: bootstrap IAM, aplicação EMR sem capacidade inicial, três artefatos em S3, 18 objetos bronze e uma chamada EMR para 2025. Sem outros anos, repetição automática, cluster fixo, NAT Gateway, endpoint interativo, crawler ou optimizer. Fontes reais foram preparadas localmente sem AWS: 109.755.723 bytes antes do manifesto, 83.722 cotações no escopo e 756 taxas. Archive SDK tem 20.635.694 bytes; estimar até 250 MiB totais de inputs, artefatos, saídas, metadata e logs neste piloto.

Tarifas públicas us-east-1 consultadas em 07/10/2026 no [catálogo oficial ElasticMapReduce](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/ElasticMapReduce/current/us-east-1/index.json): x86 USD 0,052624/vCPU-h e USD 0,0057785/GB-h. Conferir novamente antes da execução, pois current é uma URL dinâmica.

Capacidade máxima 4 vCPU/16 GB. Quinze minutos mais um minuto de margem para desligamento: (4×0,052624 + 16×0,0057785) ×16/60 = **USD 0,0807872** de computação estimada. Os primeiros 20 GB de disco padrão por worker não têm cobrança adicional, conforme [preços EMR](https://aws.amazon.com/emr/pricing/); o pedido fixa 20 GB por driver e executor.

Proposta de reserva para o piloto inteiro: **USD 0,50**. Margem cobre duração de alocação/desligamento, S3, logs, requests, catálogo, DynamoDB e eventual IPv4. Não é promessa de valor máximo faturado: timeout/budget alertam ou limitam execução, sem impor teto absoluto na cobrança. Nenhuma segunda tentativa está incluída na autorização de UMA execução; investigar antes de propor nova chamada.

Premissas: máximo 250 MiB persistidos por até 30 dias, até 20 MiB de logs e menos de 2.000 requests adicionais. Revisar antes de prosseguir caso dados, logs ou duração ultrapassem essas premissas. Não deixar workers pré-alocados; confirmar STOPPED depois da chamada.

Última leitura conhecida do budget: USD 0,335 da conta inteira, atualizado em 06/10/2026 20:19:32 São Paulo. Esse valor é antigo e pode incluir outros projetos. Reservar USD 0,70 adicionais como margem conservadora para bronze/silver ainda não refletidas (reservas anteriores completas), embora a computação estimada das duas chamadas Glue tenha sido USD 0,06417. Atualizar a leitura antes de executar.

Gate offline: `python scripts/cost_gate.py --spent 0.335 --pending 0.70 --estimate 0.50`: saldo de planejamento USD 6,465 após a reserva fixa de USD 2. Gate não é autorização e não impõe teto AWS.

Depois: registrar JobRunId e totalResourceUtilization (vCPUHour/memoryGBHour/storageGBHour quando informados), tempo, tamanho dos objetos, snapshots e custo atualizado por tag/serviço. Histórico completo recebe estimativa separada; não extrapolar aprovação deste ano para 1986–2026.
