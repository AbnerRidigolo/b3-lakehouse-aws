# Fase 3: silver incremental para revisão

Status: desenvolvimento local preparado em 06/10/2026. Nenhum recurso silver implantado, nenhum job Glue executado. EMR Serverless e backfill ainda não implementados. Bronze encerrada com o run [37549869974](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/37549869974).

## Escopo deste conjunto

- Glue 5.0, PySpark, Iceberg v2 e Glue Data Catalog. Duas tabelas: `b3_lakehouse_silver.b3_daily` e `b3_lakehouse_silver.bcb_daily`, particionadas por mês de pregão.
- Bucket silver privado com AES256/TLS, scripts revisados e ZIP determinístico; somente temporários em `temp/` expiram após um dia. Não expirar arquivos Iceberg isoladamente, pois isso corromperia snapshots.
- Job sob demanda: dois workers G.1X, timeout de dez minutos, uma execução simultânea, zero retentativas automáticas, sem conexão VPC, sem trigger nem agendamento.
- Logs com três dias de retenção. Métricas opcionais desligadas neste piloto; alarmes e painel entram na fase 5.
- Papel Glue com boundary: bronze somente leitura; escrita em silver/temp; catálogo limitado ao database e às duas tabelas; atualização DynamoDB somente de chaves `silver#*`.
- CI pode implantar scripts e infraestrutura, mas não iniciar jobs nem alterar arquivos analíticos. Boundary e políticas CI dependem de bootstrap local previamente aprovado.
- `enable_silver` e `enable_silver_permissions` começam false. Variável GitHub `ENABLE_SILVER` também precisa de autorização antes de habilitar.

## Contratos e comportamento

A leitura diária limita cada entrada ao limite da bronze, revalida o ZIP, CRC, tipo/data dos registros e rodapé, e compara SHA-256 de cada fonte com o controle bronze SUCCESS. Parsing distribuído no Spark usa as posições de bytes do layout oficial, números inteiros e Decimal; nunca float para preços.

Grão B3: ativo/data no escopo CODBDI=02 e TPMERC=010. Duplicatas exatas são removidas; duplicatas conflitantes bloqueiam a carga. OHLC deve ser positivo e abertura/fechamento precisam estar entre mínima e máxima. Volume, quantidade e negócios devem ser numéricos não negativos. ISIN vazio permanece nulo; o campo oficial também admite código interno. Preços continuam não ajustados por eventos corporativos.

`open_raw`, `high_raw`, `low_raw` e `close_raw` preservam o valor cotado original; `quotation_factor` é obrigatório e positivo. Preço unitário deriva de preço bruto / fator. `currency` é preservada; não misturar moedas históricas. `volume` é o VOLTOT monetário, separado de `quantity` (QUATOT). Retornos e identificação de eventos corporativos ficam na gold.

Grão BCB: série/data. CDI e Selic preservados em percentual diário, dólar venda em BRL/USD. Nenhuma conversão para taxa anual; nenhuma perda de precisão acima de dez casas decimais é aceita.

MERGE é determinístico por chave. Cada tabela tem commit atômico, mas as duas não constituem transação única. SUCCESS só é gravado depois dos dois MERGEs e comparação bidirecional do conteúdo relido com a entrada validada. Uma falha parcial marca FAILED; reexecução reaplica os mesmos dados e recupera a etapa, sem duplicar chaves. Rerun bem-sucedido pode criar novos snapshots/arquivos mesmo sem alterar valores. Gold futura deve exigir status silver SUCCESS.

Lease de quinze minutos supera timeout do job. Se o serviço matar o processo antes do handler de erro, RUNNING expira para permitir retomada; uma única execução simultânea evita concorrência. DynamoDB guarda contagens, hashes e status da etapa.

## Validação local

Testes unitários inteiramente offline para posições de campos, precisão, fator, faixas OHLC, unidades BCB, identificadores SQL e pacote portátil. Testes Terraform usam provider simulado para limites de execução, isolamento de IAM e ausência de início automático de jobs.

Resultado local: 26 testes Python e 18 subtestes passaram; três execuções simuladas do bootstrap e uma do módulo silver passaram. Bootstrap, módulo silver e composição dev validados; YAML dos workflows e sintaxe Python conferidos. Esses resultados não substituem a validação de integração na AWS.

Conferência manual separada, também sem rede: os payloads reais previamente baixados de 01/10/2026 produziram 317 registros únicos de 15.700 cotações, sem duplicatas conflitantes; fatores 1 e 100, moeda R$. As três observações BCB passaram. Esses arquivos privados/ignorados não fazem parte dos testes unitários nem do Git.

Não foi executado Spark/Iceberg localmente. Integração Glue, autorização efetiva, criação de tabelas, commits e recuperação precisam ser comprovados na AWS antes de declarar silver funcional. Athena entra na fase 4; EMR/histórico só após validar incremental e estimar cada execução.

## Ordem de implantação, depois de aprovada

1. Revisar plano bootstrap com `enable_silver_permissions=true`: boundary e duas políticas CI, sem alterar bronze. Aplicar somente após autorização.
2. Publicar commit autorizado; proprietário abre PR e faz merge após CI. Habilitar `ENABLE_SILVER=true` apenas no ciclo de implantação aprovado. Regerar plano contra o estado atual; não reutilizar planos antigos.
3. Revisar plano dev: apenas novos recursos silver, sem destruir bronze; aprovar ambientes `aws-plan` e `aws-apply`.
4. Conferir role/boundary, bucket privado, job com limites e ausência de trigger; conferir permissões usando IAM Simulator antes de iniciar trabalho faturado.
5. Autorizar até duas execuções explícitas para `--reference_date=2026-10-01`, uma carga e uma repetição para comprovar MERGE. Guardar IDs, status, DPUSeconds quando disponível, duração faturável, snapshots e contagens. Nenhum backfill neste piloto.
6. Medir custo atualizado e revisar resultados; depois preparar EMR Serverless com um ano, estimativa separada.

Remoção futura: dados Iceberg persistem (force_destroy=false). Remover conteúdo/tabelas exige autorização específica após preservar evidências; não usar destroy como limpeza silenciosa de dados.

## Fontes oficiais consultadas em 06/10/2026

- [Layout B3 revisão 02](https://www.b3.com.br/data/files/33/67/B9/50/D84057102C784E47AC094EA8/SeriesHistoricas_Layout.pdf).
- [Iceberg no Glue](https://docs.aws.amazon.com/glue/latest/dg/aws-glue-programming-etl-format-iceberg.html): Glue 5.0 inclui Iceberg 1.7.1; catálogo e extensões Spark configurados no job.
- [MERGE Spark no Iceberg](https://iceberg.apache.org/docs/latest/spark-writes/).
- [Workers Glue](https://docs.aws.amazon.com/glue/latest/dg/add-job.html) e [logs Glue 5.0](https://docs.aws.amazon.com/glue/latest/dg/monitor-continuous-logging.html).
- [Provider AWS 6.66 job](https://github.com/hashicorp/terraform-provider-aws/blob/v6.66.0/internal/service/glue/job.go), [database](https://github.com/hashicorp/terraform-provider-aws/blob/v6.66.0/internal/service/glue/catalog_database.go) e [S3 object](https://github.com/hashicorp/terraform-provider-aws/blob/v6.66.0/internal/service/s3/object.go): APIs e tags revisadas para preparar IAM, não prova de autorização efetiva.
- [Tags Glue](https://docs.aws.amazon.com/glue/latest/dg/monitor-tags.html): tag Project nos recursos Terraform compatíveis. Tabelas não estão na lista oficial de recursos Glue com AWS tags; identificação por database dedicado, job e bucket marcados, sem prometer cobertura de custo de cada item do catálogo.
- [Estimativa deste piloto](costs/silver.md).
