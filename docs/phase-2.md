# Fase 2: ingestão bronze

Status em 06/10/2026: código local e testes validados; infraestrutura bronze ainda não implantada. Fundação validada em plan/apply no GitHub, run 36923751428, com zero mudanças.

## Fontes e contrato

- B3: ZIP diário original, sem transformação, armazenado por reference_date. Cada linha TXT tem 245 bytes; validar ZIP/CRC, nomes dos membros, tipos 00/01/99 e data do pregão. Escopo para silver: CODBDI 02 (lote padrão) e TPMERC 010 (vista). Bronze preserva também os registros fora desse escopo. Preços não ajustados por eventos corporativos.
- Layout de referência: revisão 02 de 05/10/2020, https://www.b3.com.br/data/files/33/67/B9/50/D84057102C784E47AC094EA8/SeriesHistoricas_Layout.pdf . Página da fonte: https://www.b3.com.br/pt_br/market-data-e-indices/servicos-de-dados/market-data/historico/mercado-a-vista/cotacoes-historicas/ .
- Divergência verificada manualmente no arquivo oficial diário de 01/10/2026: 15.702 registros físicos, 15.700 cotações; rodapé declara 15.700, embora o PDF descreva total incluindo header/trailer. O validador aceita explicitamente total físico ou total de cotações e registra trailer_count_mode. Qualquer outra contagem falha. Não esconder a divergência nem alterar o dado original.
- BCB SGS: 12 CDI (% ao dia), 11 Selic (% ao dia) e 1 dólar venda (moeda corrente por USD). Metadados CDI verificados com sessão HTTP no SGS: https://www3.bcb.gov.br/sgspub/consultarmetadados/consultarMetadadosSeries.do?method=consultarMetadadosSeriesInternet&hdOidSerieSelecionada=12 . As páginas do catálogo tentadas para CDI não estavam acessíveis; os metadados oficiais SGS confirmaram código, nome e unidade.
- Selic: https://dadosabertos.bcb.gov.br/pt_BR/dataset/11-taxa-de-juros---selic ; dólar: https://dadosabertos.bcb.gov.br/dataset/1-taxa-de-cambio---livre---dolar-americano-venda---diario .
- Cada consulta incremental usa data inicial/final explícitas. A função de paginação usa no máximo 3.650 dias por janela, abaixo de dez anos mesmo com anos bissextos; paginação sem gaps ou sobreposição. Ela prepara a futura carga histórica, ainda não executada. Resposta vazia, data errada ou valor não finito interrompem a carga.

Verificação manual dos endpoints em 06/10/2026, fora dos testes: B3 464.064 bytes, 15.700 cotações, 317 no escopo; BCB uma observação por série para 01/10/2026. Não houve gravação desses dados na AWS.

## Comportamento

Lambda Python 3.12, 512 MB, timeout 180 s, sem VPC. Downloads limitados a 32 MiB por fonte; TXT B3 descompactado limitado a 128 MiB. ZIP lido em memória, sem extrair caminhos. URLs construídas internamente; usuário não fornece endereço de download.

S3 privado, AES256 e TLS; chaves bronze/source=.../reference_date=AAAA-MM-DD/raw.zip ou raw.json. Metadados guardam SHA-256, contagem e versão da validação. Upload condicional evita sobrescrever objetos. Bucket não é destruído com objetos automaticamente; dados não expiram por lifecycle.

DynamoDB on demand guarda status por data e etapa bronze. Lease de 300 s evita duas execuções simultâneas da mesma data; limite Lambda é 180 s. SUCCESS bloqueia nova coleta; FAILED pode retomar pelos objetos já validados. Só registrar SUCCESS depois das quatro fontes. Registro de controle tem TTL de 90 dias; após sua expiração, os objetos S3 continuam protegendo contra duplicação. Esse controle é o watermark por data, sem pular falhas intermediárias.

EventBridge Scheduler criado DISABLED: dias úteis às 21h em America/Sao_Paulo, data derivada do scheduled-time. Dias úteis não equivalem a calendário de pregões: feriados e indisponibilidade de fonte podem falhar. A habilitação diária exige aprovação separada após o teste manual; Step Functions e tratamento completo de falhas entram na fase 5. Logs retidos por três dias.

## Infraestrutura e CI

Módulo infra/modules/bronze: S3, DynamoDB, Lambda, logs e Scheduler. Papéis de serviço com permissions boundary criada no bootstrap; boundary permite apenas objetos bronze, controle de execução, logs da função e invocação da mesma Lambda. CI plan lê configurações; CI apply gerencia apenas os recursos nomeados da fase. PassRole limitado aos dois papéis e serviços Lambda/Scheduler. DescribeLogGroups requer Resource=*; nenhuma outra ampliação genérica foi adicionada.

Defaults enable_bronze_permissions=false no bootstrap e enable_bronze=false em dev. A publicação do código não implanta recursos novos. Permissões bootstrap serão aplicadas por sessão local após revisão do plano; a implantação dev será pelo GitHub Actions. Pacote ZIP determinístico gerado em artifacts/ ignorado, a partir de handler.py no commit revisado, tanto em plan quanto em apply.

## Validação antes da implantação

- pytest: 13 testes e 18 subtests passaram offline, incluindo dados inválidos, contagem, janelas, falha parcial, retomada e idempotência, além dos controles de custo/criptografia anteriores.
- Terraform: seis runs simulados passaram (dois bootstrap, três budgets, um bronze); validação de bootstrap, bronze e dev passou.
- Sintaxe dos workflows e shell verificada; pacote ZIP reproduzível.
- Nenhum teste chama internet ou AWS. A verificação manual de fontes fica separada.

## Próximos passos autorizáveis

1. Publicar os commits mediante aprovação por commit; proprietário abre/mescla PR. Com flags falsas, os planos AWS devem continuar sem novos recursos, a confirmar nos logs.
2. Atualizar consumo real e pendente; revisar estimativa em costs/bronze.md.
3. Gerar plano bootstrap com enable_bronze_permissions=true; obter autorização para aplicar boundary e duas políticas CI.
4. Habilitar ENABLE_BRONZE no GitHub após aprovação do plano dev. Manter BRONZE_SCHEDULE_ENABLED ausente/false.
5. Aprovar plan/apply pelo proprietário; conferir somente recursos da fase 2.
6. Invocar Lambda manualmente para reference_date=2026-10-01; conferir quatro objetos, checks e SUCCESS. Repetir a mesma data, verificar ALREADY_SUCCESS e ausência de novos objetos.
7. Registrar logs, contagens, hashes e consumo. Encerrar a fase somente após carga real e aprovação do proprietário.
