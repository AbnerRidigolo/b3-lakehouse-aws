# Estimativa do primeiro piloto gold — não autorizado ainda

Região us-east-1, plano FREE preservado, sem descontos de créditos no cálculo. Proposta: uma publicação de imagem, implantação da infraestrutura e uma execução, sem retries. Reserva proposta **USD 1,00**, condicionada ao gasto bruto atualizado mais consumo pendente mais USD 2 de reserva permanecerem abaixo do teto total de USD 10.

| Item | Hipótese conservadora do piloto |
| --- | --- |
| Athena | Até 100 consultas, cada uma limitada a 1 GiB: aproximadamente USD 0,54 a USD 5/TB. A quantidade é hipótese de planejamento, não bloqueio agregado do workgroup. |
| Fargate e IPv4 | Reservar USD 0,05 para uma tarefa de 0,5 vCPU/1 GiB com processo limitado a 20 minutos, acrescido de provisionamento/pull; observar duração real e interromper travamento. |
| ECR | Até 1 GB de imagem por um mês: aproximadamente USD 0,10. Confirmar tamanho depois do build; imagens maiores exigem revisão. |
| S3, catálogo e logs | Reserva de USD 0,20 para volume pequeno, requisições e armazenamento inicial; conciliar consumo real após a execução. |
| Margem | USD 0,11 dentro da reserva de USD 1. Não autoriza execuções extras. |

O orçamento e o limite por consulta não constituem teto de gasto agregado. Consultas interrompidas podem ter consumo faturado. Sem autorização e conciliação, não executar o piloto. Se qualquer serviço exigir mudança do plano gratuito, interromper e informar o proprietário.

Não há serviço ECS permanente. Imagens e dados continuam com armazenamento cobrável após a tarefa terminar. Resultados Athena expiram em um dia e logs em três; dados gold e imagens com tag são preservados, exigindo decisão explícita de retenção/encerramento.

Fontes consultadas em 12/10/2026: [Athena](https://aws.amazon.com/athena/pricing/) (USD 5/TB nos exemplos), [Fargate](https://aws.amazon.com/fargate/pricing/) (cobrança por recursos e duração), [IPv4 público](https://aws.amazon.com/vpc/pricing/) (USD 0,005/h), [ECR](https://aws.amazon.com/ecr/pricing/) (USD 0,10/GB-mês nos exemplos). A reserva Fargate é uma margem de planejamento, não cotação final calculada pelo serviço.
