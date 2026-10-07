# Piloto histórico 2025: preparado, ainda não implantado

Piloto autorizado em 07/10/2026, com reserva USD 0,50 para uma execução. Permissões bootstrap implantadas e 18 objetos históricos publicados na bronze, com SUCCESS no DynamoDB. A aplicação EMR ainda não foi implantada e nenhum processamento EMR foi executado. Bronze e silver diárias continuam implantadas.

## Fontes verificadas e preparação real local

Arquivo anual oficial [COTAHIST_A2025.ZIP](https://bvmf.bmfbovespa.com.br/InstDados/SerHist/COTAHIST_A2025.ZIP), 89.056.788 bytes, membro COTAHIST_A2025.TXT. O [layout oficial B3](https://www.b3.com.br/data/files/33/67/B9/50/D84057102C784E47AC094EA8/SeriesHistoricas_Layout.pdf) continua sendo a referência das posições e tipos.

Preparação local em streaming: 3.174.698 cotações brutas; 83.722 no escopo CODBDI=02, TPMERC=010, em 250 dias; 83.722 chaves únicas, zero conflitos. O parser silver já revisado passou para todas as cotações no escopo. Moeda, fator de cotação e preços não ajustados são preservados.

BCB SGS 12 (CDI), 11 (Selic) e 1 (dólar venda), intervalo 01/01/2025–31/12/2025: 756 observações únicas. Todas as séries cobrem os 250 dias B3; observações em dias BCB adicionais também são preservadas. Cada consulta usa um ano, abaixo da janela máxima de dez anos.

Os 17 arquivos preparados somam 109.755.723 bytes. Manifesto é um arquivo adicional: 18 objetos a publicar. ZIP original e três JSON originais são preservados. Doze arquivos mensais contêm somente os registros no escopo (posições originais, convertidos para UTF-8 para leitura distribuída e restaurados para Latin-1 antes de interpretar bytes). rates.jsonl contém valores decimais como texto e unidades explícitas. Essa preparação filtra/valida, sem calcular preços ou retornos. Preços, tipagem, deduplicação e MERGE são executados no Spark.

Manifesto registra hashes, tamanhos, origens e contagens. ZIP lido sem extração de caminhos, com limite de 128 MiB compactados, 2 GiB expandidos e linhas limitadas a 248 bytes na leitura. Rodapé precisa corresponder a todas as cotações ou a todos os registros físicos; modo observado é registrado. Dados e manifesto permanecem em local/history-2025/, fora do Git.

## Infraestrutura e execução propostas

- EMR Serverless em us-east-1, release emr-7.10.0, x86, sem workers pré-inicializados, sem VPC/NAT, sem cluster fixo ou endpoint interativo solicitado.
- Capacidade máxima total: 4 vCPU, 16 GB de memória, 40 GB de disco padrão. Pedido: driver 2 cores/6g, um executor 2 cores/6g, dynamicAllocation=false; 20 GB de disco por worker. Limite de execução de quinze minutos, uma tentativa, uma execução simultânea. Auto-stop após um minuto ocioso.
- Sem chamadas de download da internet em workers faturados: todas as entradas já estarão na bronze e terão hashes conferidos pelo job, em streaming.
- SDK Python fixado e empacotado como archive extraído; não depender da presença de boto3 na imagem nem tentar carregar dados internos do SDK diretamente de ZIP em PYTHONPATH.
- IAM runtime com boundary limitada à bronze histórica 2025, scripts history-*, duas tabelas silver existentes e chave de execução history#2025. Sem criar tabelas ou modificar status bronze. Trust limitado ao ARN da aplicação criada e à conta.
- Bootstrap: boundary, duas políticas gerenciadas CI e dois vínculos; cinco recursos. Papel service-linked oficial EMR (serviço ops.emr-serverless.amazonaws.com) somente se não existir, somando uma criação. Verificar existência antes do plano; preencher existing_emr_service_role_arn quando presente. Caso criado pelo projeto, permanece protegido por prevent_destroy, pois é compartilhável e não cobra compute.
- CI pode criar/configurar a aplicação marcada Project=b3-lakehouse-aws e Component=history-2025 e implantar scripts. Não pode StartApplication/StartJobRun ou PassRole. Políticas gerenciadas evitam crescimento do limite agregado de inline policies já usadas por bronze/silver.
- Dev: seis criações (aplicação, papel, política runtime e três scripts). Flags enable_history/enable_history_permissions e variável GitHub ENABLE_HISTORY começam desativadas.
- Logs em S3 history-logs/, sem managed persistence solicitada. Registrar tamanho e limpar logs depois de preservar evidências, sob autorização. Sem optimizer Iceberg ou agendamento histórico.

## Contratos e retomada

Publicação local por AWS CLI oficial, credenciais temporárias e conta verificada. If-None-Match impede sobrescrever objetos. Reexecução da publicação aceita apenas arquivos com mesmo hash/tamanho; manifesto publicado por último, seguido de bronze#year=2025 SUCCESS no DynamoDB. O script não inicia jobs. Não executá-lo antes de aprovar os custos de escrita/armazenamento.

EMR exige esse SUCCESS e hash de manifesto idêntico, confere os 17 hashes das entradas e aplica o mesmo parser da silver em leitura Spark distribuída. Duplicatas exatas são removidas; conflitos e contagens divergentes bloqueiam. Taxas precisam ter data/precisão válidas e chaves únicas. MERGE usa ativo/data ou série/data; preserva 2026 e outras datas fora do ano solicitado.

Cada tabela tem commit próprio. SUCCESS histórico só após comparar bidirecionalmente os dados Iceberg relidos para 2025 com a entrada validada. Falha marca FAILED; lease de vinte minutos permite retomada após timeout. Retomar cria novo trabalho faturado e exige autorização própria se a primeira tentativa falhar. Não prometer transação única entre as tabelas nem correção de eventos corporativos.

## Procedimento após aprovação

1. Conferir budget atualizado, custo ainda atrasado e compatibilidade da conta Free Tier; não converter plano ou habilitar Organizations/SSO.
2. Verificar AWSServiceRoleForAmazonEMRServerless, preparar plano bootstrap e aplicar apenas permissões esperadas, após revisão. Nenhuma ampliação IAM administrativa para CI.
3. Publicar commit autorizado; proprietário abre PR/merge. Habilitar ENABLE_HISTORY e revisar plano dev, preservando bronze/silver. Não usar planos salvos antes de mudanças de estado.
4. Publicar fontes por `python scripts/publish_history.py --account-id <conta> --profile b3-dev`. Conferir hashes e status.
5. Recuperar IDs Terraform da aplicação e do papel. `python scripts/history_request.py --application-id <id> --account-id <conta> --manifest-sha <hash>` gera somente local/emr-2025-request.json. Token idempotente deriva de aplicação e manifesto; não reutilizar com parâmetros diferentes.
6. Dentro da autorização específica, iniciar UMA chamada pela AWS CLI com o JSON, monitorar JobRunId, estado, tempo e totalResourceUtilization; capturar logs em falha. Não repetir automaticamente. Confirmar aplicação parada ao terminar (parar explicitamente se necessário dentro do piloto).
7. Conferir history#2025 SUCCESS, 83.722 cotações/756 taxas, snapshots, hashes e preservação dos 317 registros B3/3 taxas de 2026 já implantados. Registrar custo estimado e billing por tag/serviço com período explícito.

## Validação e limitações

Testes offline cobrem rodapé anual, nomes ZIP inseguros, ano incorreto/incompleto, partições, cobertura e conflitos de taxas, pedido com capacidade/timeout/tentativa limitados e pacotes portáteis. Terraform usa provider simulado. SDK extraído carregou os modelos S3/DynamoDB offline. Nenhum teste chama AWS ou internet. Resultado: 33 testes Python e 18 subtestes passaram; quatro runs simulados do bootstrap e um do módulo histórico passaram. Composição dev validada sem backend, sintaxe Python/YAML conferida.

Preparação real local é evidência separada dos testes unitários. Não houve execução Spark/EMR, publicação AWS das fontes, criação da aplicação ou alteração das tabelas. Integração e autorização efetiva precisam ser comprovadas depois da aprovação.

Este código só executa 2025. Não afirmar backfill completo desde 1986: outros anos exigem revisão do escopo IAM, cobertura BCB e regras históricas, além de estimativa e autorização próprias. Gold/dbt, Athena e orquestração ponta a ponta continuam pendentes.

Fontes técnicas: [service-linked role](https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/using-service-linked-roles.html), [Iceberg no EMR](https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/using-iceberg.html), [Spark/recursos](https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/jobs-spark.html), [versões](https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/release-versions.html), [Python archives](https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/using-python-libraries.html), [provider AWS 6.66 aplicação](https://github.com/hashicorp/terraform-provider-aws/blob/v6.66.0/internal/service/emrserverless/application.go) e [estimativa](costs/history.md).


## Preparação AWS concluída em 07/10/2026

Bootstrap: seis criações, zero alterações e exclusões, incluindo o service-linked role que não existia. ENABLE_HISTORY habilitada para o ciclo autorizado. Plano dev revisado: seis criações, zero alterações/exclusões; ainda não aplicado. PR #11 aberto; validação offline do commit inicial passou.

Publicação CLI concluída: 18 objetos em bronze/history/year=2025/. Listagem S3 e leitura consistente DynamoDB confirmaram bronze#year=2025 SUCCESS, 83.722 cotações e 756 taxas. Manifesto e arquivos locais foram conferidos por SHA-256 antes de publicar, e objetos existentes só são aceitos com mesmo hash/tamanho. EMR verificará os hashes dos payloads na execução.

A simulação identificou um erro no escopo IAM de CreateApplication: essa ação não suporta ARN de recurso. Corrigida somente essa criação para Resource=*, condicionada a aws:RequestedRegion=us-east-1, Project=b3-lakehouse-aws e Component=history-2025. Permissões sobre aplicações existentes continuam limitadas por ARN/tags; nenhuma permissão StartApplication/StartJobRun foi adicionada. [Referência oficial](https://docs.aws.amazon.com/service-authorization/latest/reference/list_emr-serverless.html). Plano da correção: zero criações, uma política alterada, zero exclusões; aplicado dentro da autorização do piloto. Teste Terraform cobre região/tags. Simulação AWS posterior permitiu o piloto e negou outra região e outro projeto.

Budget observado antes do upload: conta USD 0,431 (07/10/2026 08:02:17 São Paulo); projeto USD 0,066 (07:54:01). Esses valores têm atraso, não incluem necessariamente os uploads recentes e não são custo final. Não houve chamada EMR.
