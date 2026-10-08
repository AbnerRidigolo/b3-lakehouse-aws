# Histórico completo com Glue — preparado, ainda não implantado

O proprietário autorizou ampliar o Glue para o histórico completo, mantendo o plano FREE. O EMR continua bloqueado pelo plano da conta. Esta mudança habilita os anos completos 1986–2025, um por execução. Não afirma que esses anos já foram carregados.

## Contrato e rastreabilidade

- Aceita os nomes oficiais COTAHIST_AAAAA.TXT e COTAHIST.AAAAA no ZIP, sem extrair caminhos. Cabeçalho, ano, tamanho e rodapé continuam obrigatórios.
- `python scripts/prepare_history.py --year ANO --historical-contract` valida todas as linhas localmente antes de qualquer upload ou job. Diretório existente é recusado para evitar misturar preparações.
- Linhas com campos ou OHLC inválidos ficam em `quarantine.jsonl`: linha física, texto original, motivo e SHA-256. O ZIP original permanece intacto. Total no escopo = aceitas + quarentena. Esta exceção foi autorizada pelo proprietário; conflitos de chave continuam bloqueando a preparação.
- `rate-coverage.json` distingue datas anteriores ao início das séries de observações ausentes. Nenhuma taxa é inventada ou preenchida. A gold deverá impedir comparações de CDI em intervalos com cobertura incompleta.
- SGS 1 usa unidade monetária corrente por dólar: antes de julho de 1994 o campo unit passa a `current_currency/USD`. Valores brutos não são convertidos. BRL/USD só é usado a partir do Real; a gold deverá separar moedas e mudanças monetárias.
- O caminho normal, sem `--historical-contract`, continua exigindo cobertura completa do BCB.

## Infraestrutura preparada

O job existente mantém nome físico com 2025 para evitar substituição, dois G.1X, timeout de quinze minutos, zero retries, concorrência um e nenhum agendamento. O ano passa a argumento explícito com default 2025; o código aceita somente 1986–2025. Engine, destinos e configuração permanecem fixos.

A política compartilhada e a boundary permitem somente prefixos/controles históricos dos anos 1986–2025. Os demais privilégios permanecem iguais. O publicador exige `--year`; verifica hashes antes de escrever e mantém objetos imutáveis. Dynamo registra também a quantidade em quarentena.

## Evidência local em 07/10/2026

O ZIP oficial de 1986 tem 177.981 registros de cotação, dos quais 92.653 no escopo. Foram aceitos 92.650 sem duplicatas e preservadas três linhas em quarentena: CHA 2 em 07/04, MVI 2 em 06/05 e BDL 2 em 30/05, todas com abertura/fechamento fora da mínima/máxima. Há 13.270 registros válidos em CR$ e 79.380 em CZ$.

BCB: 607 observações. Em relação aos pregões aceitos, faltam 40 dias anteriores ao início do CDI, 99 anteriores à Selic e três observações de CDI após seu início (07, 11 e 13/03/1986). Dólar cobre todos esses pregões. Arquivos de auditoria ficam em `local/history-1986-checked/`, ignorados pelo Git. Nada de 1986 foi enviado à AWS nesta validação.

## Implantação e custo pendentes

Revisar os planos do bootstrap (boundary) e dev (job/política/artefatos), atualizar a estimativa de custo e obter autorização antes de aplicar e executar. Processar e validar cada ano, registrar sucesso e custo antes do seguinte. Ainda falta preparar/verificar 1987–2024; 2025 já está implantado. O ano corrente de 2026 requer completar o incremental, não usar um arquivo anual como se fosse um ano encerrado.

O custo observado do piloto não garante custo igual para outros anos. Quarenta execuções no timeout máximo excederiam a reserva operacional do projeto; não iniciar um lote irrestrito. O teto total continua USD 10, com USD 2 reservados para atraso de billing/limpeza.

## Referências

- [B3 — layout oficial](https://www.b3.com.br/data/files/33/67/B9/50/D84057102C784E47AC094EA8/SeriesHistoricas_Layout.pdf).
- [BCB — Selic, início 04/06/1986](https://dadosabertos.bcb.gov.br/pt_BR/dataset/11-taxa-de-juros---selic).
- [BCB — câmbio e unidade monetária corrente](https://dadosabertos.bcb.gov.br/dataset/1-taxa-de-cambio---livre---dolar-americano-venda---diario).
- CDI: SGS 12, primeira observação 06/03/1986 na resposta oficial anual preservada localmente.

Validação do código: 39 testes Python e 18 subtestes passaram; sete runs Terraform simulados passaram (bootstrap, history e history-glue), incluindo limite de tamanho da política. Pacotes históricos gerados e diff sem erros de whitespace.
