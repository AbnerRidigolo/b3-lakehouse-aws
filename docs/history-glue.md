# Backfill 2025 no Glue — implantado e validado

Em 07/10/2026, o proprietário autorizou substituir o EMR por Glue neste piloto, preservando o plano FREE. Reserva USD 0,50, UMA execução de 2025. O EMR permanece preparado e não executado, devido a [SubscriptionRequiredException](emr-subscription-block.md). Nenhum upgrade de conta foi solicitado.

## Conjunto preparado para implantação

- Novo job b3-lakehouse-aws-history-2025-glue, Glue 5.0, dois G.1X, timeout quinze minutos, uma execução simultânea, zero retentativas automáticas. Sem trigger, VPC/NAT ou workers fixos.
- Ano 2025, engine Glue, buckets, tabela de controle e database fixados em non_overridable_arguments. Usa o runtime Iceberg nativo do Glue e SDK boto3 da plataforma; nenhuma instalação durante a execução faturada.
- Parser e MERGE existentes reutilizados. Código aceita argumentos de framework Glue, mantendo os parâmetros de dados obrigatórios; EMR continua rejeitando argumentos desconhecidos.
- Dois log groups com retenção três dias, papel runtime e política limitada às entradas históricas 2025, duas tabelas silver existentes, prefixos silver/temp e registro history#2025. Boundary também limita logs aos grupos desse job.
- CI pode provisionar esse job e PassRole somente do papel histórico Glue para glue.amazonaws.com. Não pode iniciar Glue/EMR jobs. Bootstrap previsto: três políticas atualizadas, nenhuma criação ou exclusão.
- Flags: ENABLE_HISTORY=true preserva artefatos; HISTORY_EMR_ENABLED=false evita a criação bloqueada; ENABLE_HISTORY_GLUE=true provisiona somente Glue. Desabilitar todo enable_history não é a solução, pois destruiria os três objetos de scripts no estado.
- Plano dev revisado: cinco criações (job, papel, política e dois grupos de logs), duas atualizações de artefatos, zero exclusões; bronze e silver diárias preservadas. Script histórico atualizado para Glue. SDK archive normalizado: removido bin/jp.py, console entrypoint com caminho de interpretador diferente entre Windows/Linux, que não é usado pelos workers. Modelo e código dos pacotes comparados com o SDK publicado: demais payloads iguais.

## Dados e validação

18 objetos bronze imutáveis já publicados; bronze#year=2025 SUCCESS. Manifesto: 83.722 cotações no escopo, 250 pregões e 756 taxas. Job verifica os hashes de todos os arquivos antes de processar e compara bidirecionalmente cada tabela Iceberg relida para 2025 com os dados de entrada antes de gravar SUCCESS. A data 01/10/2026 já implantada deve permanecer intacta.

Commits de tabelas são separados: uma falha parcial marca FAILED; lease de vinte minutos permite retomada após timeout, mas nenhuma segunda execução é autorizada automaticamente. Não afirmar resultado histórico ou idempotência anual antes da execução real.

Resultado local: 34 testes Python e 18 subtestes passaram; quatro runs simulados bootstrap, dois módulo history e um módulo history-glue passaram. YAML e sintaxe conferidos; nenhum teste acessa AWS/internet. Planos reais são verificações separadas e não aplicaram recursos novos.

## Custo e próximos passos

Computação máxima estimada: 2 DPU ×15/60 h×USD 0,44 = USD 0,22 pela [referência oficial Glue](https://aws.amazon.com/glue/pricing/). Reserva total USD 0,50 cobre margem de faturamento e serviços auxiliares; não é teto técnico absoluto. Sem repetição, outros anos ou conversão de plano. Atualizar o budget antes de iniciar.

Publicar commit somente após autorização, proprietário abre PR/merge. Aplicar o bootstrap revisado, configurar as flags e revisar novo plano GitHub contra o estado atual. Depois do apply, verificar limites, arquivos, IAM, fonte SUCCESS e inexistência de execução anterior antes de iniciar UMA chamada. Registrar JobRunId, DPUSeconds, contagens, snapshots, preservação de 2026 e billing com período explícito. Histórico completo, gold e orquestração continuam pendentes.

## Execução concluída

[Uma carga real de 2025 passou](history-glue-evidence.md): 83.722 cotações e 756 taxas, Glue SUCCEEDED e DynamoDB SUCCESS. Snapshots adicionaram os dados sem remover registros/arquivos de 2026. ExecutionTime 110 segundos, DPUSeconds 221, computação estimada USD 0,02701; billing ainda atrasado. Plano FREE permaneceu ativo. Sem rerun anual ou outros anos. As seções anteriores descrevem a configuração revisada do piloto já implantado.
