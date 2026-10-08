# Evidências — histórico 1986 e lote 1987–1994

Validação real em 08/10/2026, conta do projeto em us-east-1. Os anos 1986–1994 e 2025 estão carregados, além do incremental de 01/10/2026. Total atual: 790,614 cotações e 7,327 taxas nas duas tabelas Iceberg. Gold e orquestração ponta a ponta continuam pendentes.

## Lote autorizado de 1987–1994

Oito execuções únicas SUCCEEDED, com DynamoDB SUCCESS e leitura de volta verificada pelo job. Acrescentadas 613.925 cotações e 5.961 taxas. Oito linhas em quarentena, preservadas com texto original, posição, motivo e SHA-256. Custo de computação estimado pelo consumo: USD 0.27952; reserva autorizada USD 2. Não representa o faturamento final de S3, logs e demais serviços.

Os snapshots de cada tabela têm como pai o snapshot imediatamente anterior e operação append. Contagens totais cresceram exatamente pelo lote de cada ano, sem remoção de registros ou arquivos de dados. Isso preserva as cargas anteriores de 1986, 2025 e 2026. Não foi realizado rerun desses anos; não afirmar idempotência anual testada.

Execuções e contagens:

- 1987: 89398 cotações, 748 taxas, 234.0 DPU-segundos; run `jr_b3a74b589e4d801d3ea616de1e954d57088fde18a435b6116a33c0af356eab3a`.
- 1988: 97060 cotações, 747 taxas, 302.0 DPU-segundos; run `jr_e0949b7644f5b4187b2f0d0a98f3f0c46bfacdc04feb0f0c64eec227dc379ea9`.
- 1989: 92814 cotações, 741 taxas, 404.0 DPU-segundos; run `jr_597f53b74dd10d14831c1cef7c49aba85f8793861b7f5f9a3de43be910c9296d`.
- 1990: 69352 cotações, 736 taxas, 289.0 DPU-segundos; run `jr_3f835c330dcb3cc063e0d732c62580d77ce13169701d057eb9bac458dca333b2`.
- 1991: 69475 cotações, 751 taxas, 221.0 DPU-segundos; run `jr_aaf163c0f22310877b19b2070b7612a259bd96a50102985c1903286f1c647ada`.
- 1992: 64154 cotações, 747 taxas, 227.0 DPU-segundos; run `jr_a37f3cf01eb4524761b5f1ac5e04eb9e44b3bcaeccd34daac507da433ef45614`.
- 1993: 64952 cotações, 747 taxas, 301.0 DPU-segundos; run `jr_c1e222052faa3e9907b4eff20ddcb5925567d0662350f25cc4cf0d84cf98902e`.
- 1994: 66720 cotações, 744 taxas, 309.0 DPU-segundos; run `jr_7008a6a5b732d76999b5d7aeaf968988d36ec60f43e9725e3eba1c278bbdfced`.

## Interrupção controlada

A primeira solicitação de início de 1992 recebeu ConcurrentRunsExceededException após 1991 aparecer SUCCEEDED. O lote parou. Uma consulta posterior confirmou que nenhuma execução de 1992 havia sido criada e que não havia jobs ativos. Após o proprietário pedir continuidade, somente 1992–1994 foram retomados; a solicitação rejeitada ficou registrada e adicionou-se pausa de 45 segundos entre anos. Nenhum job foi repetido automaticamente.

## Ano de 1986

Carga anterior deste ciclo: 92.650 cotações, 607 taxas, três linhas em quarentena. Glue SUCCEEDED, 142 segundos, 284 DPU-segundos; computação estimada USD 0,03471. Evidências detalhadas em arquivos locais ignorados pelo Git.

## Histórico ainda não carregado

Os 40 anos completos de 1986–2025 passaram pela preparação local e conferência de hashes. O período restante 1995–2024 contém 2.394.863 cotações válidas, 22.590 taxas e 363 registros em quarentena, aproximadamente 1,15 GB de arquivos preparados e fontes. Esses 30 anos não foram publicados nem executados na AWS nesta etapa.

O arquivo oficial de 2001 tem o membro COTAHIST_A2001, sem extensão .TXT; a validação agora aceita também esse nome exato para o ano solicitado. Cabeçalho, comprimento, ano, CRC e rodapé permanecem obrigatórios. Respostas HTTP 502 e uma página HTML no endpoint BCB foram rejeitadas; as consultas públicas foram retomadas e validadas antes de gerar manifestos.

As lacunas do BCB são explícitas e não preenchidas. Valores de câmbio anteriores ao Real mantêm unidade monetária corrente/USD. Comparações futuras com CDI precisam de cobertura completa no intervalo; retornos não podem cruzar mudanças monetárias como se fossem a mesma moeda.

## Limites e faturamento

Dois G.1X por execução, timeout 15 minutos, uma execução simultânea, sem retries e sem agendamento. Scheduler continua desativado. O último gasto bruto consultado antes do ciclo era USD 0,466, com atraso de atualização; não tratar esse valor como custo final do projeto nem subtrair créditos para representar consumo.

Referência de cálculo: [AWS Glue, USD 0,44 por DPU-hora](https://aws.amazon.com/glue/pricing/). Evidências brutas: local/batch-1987-1994 e local/history-1986-evidence.json, ignoradas pelo Git. O teto total segue USD 10, incluindo reserva de USD 2 para atraso de billing e encerramento.

Validação offline: 40 testes e 18 subtestes passaram. A conta permaneceu FREE/ACTIVE na consulta durante o lote; não houve conversão de plano.
