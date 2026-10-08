# Bloqueio de habilitação EMR — 07/10/2026

[Workflow 37678905523](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/37678905523): plan passou; apply falhou em CreateApplication com HTTP 403, SubscriptionRequiredException, mensagem "The AWS Access Key Id needs a subscription for the service". RequestID 9277c7f3-d9cb-4e1b-a5b4-f7d8ecefa6e4, em 07/10/2026 20:21:32 UTC (17:21:32 São Paulo).

Antes da falha, os três objetos scripts/history-job.py, history-libs.zip e history-sdk.zip foram publicados no bucket silver. Estado remoto Terraform conferido: esses três objetos estão registrados; aplicação EMR e papel runtime histórico não constam no estado. Não houve StartJobRun ou execução de compute EMR. Bronze e silver existentes permaneceram no estado e não foram destruídas.

CLI Free Tier GetAccountPlanState confirmou accountPlanType=FREE, accountPlanStatus=ACTIVE e créditos restantes USD 133,25. Expiração informada 02/12/2026 01:41:54 UTC (01/12/2026 22:41:54 São Paulo). Consulta somente leitura; não foi feita conversão do plano, adesão a Organizations ou alteração de assinatura.

A [documentação Free Tier](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-FAQ.html) informa restrições de acesso a determinados serviços no plano gratuito. O erro observado é compatível com bloqueio de habilitação/assinatura da conta; a disponibilidade específica do EMR nessa conta precisa de confirmação pela AWS. Não concluir somente pela documentação genérica que todas as contas gratuitas têm exatamente a mesma restrição EMR. Autorizações IAM de CreateApplication foram previamente validadas no simulador, com região e tags do piloto.

Não repetir o apply indiscriminadamente: as criações de EMR continuam pendentes e os artefatos já existem. Não desabilitar enable_history em um apply sem revisar, pois isso proporia excluir os três artefatos registrados. Preservar estado e objetos enquanto o proprietário escolhe o caminho.

## Alternativa Glue autorizada, implantação pendente

Preservar o plano FREE e executar o ano 2025 num job Glue PySpark sob demanda. As mesmas entradas bronze validadas, parser, duas tabelas silver Iceberg e contrato de qualidade seriam reutilizados. Configuração proposta: Glue 5.0, dois workers G.1X, timeout quinze minutos, uma execução simultânea, zero retentativas automáticas, sem VPC/NAT. Uma chamada para 2025, sem outros anos.

Estimativa de computação: 2 DPU ×15/60 h×USD 0,44 = USD 0,22, usando a tarifa de referência [Glue](https://aws.amazon.com/glue/pricing/). Reserva proposta USD 0,50 para o piloto, incluindo margem de serviços auxiliares. Revalidar budget e plano antes de aplicar. O proprietário aprovou trocar este backfill para Glue e reservar USD 0,50 para uma execução. Nenhum job Glue histórico foi criado ou executado.

Se aprovada a alternativa, preparar módulo/flags que preservem os três artefatos EMR existentes sem tentar criar uma aplicação indisponível em cada deploy. Registrar EMR como preparado e não executado; não afirmar histórico validado até uma carga real terminar. Histórico completo, gold e orquestração seguem pendentes.
