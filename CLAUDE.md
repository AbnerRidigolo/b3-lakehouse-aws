# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Visão geral

Lakehouse de cotações B3 (arquivos COTAHIST) e séries do Banco Central (SGS 12 = CDI, 11 = Selic, 1 = dólar venda) na AWS (`us-east-1`): Lambda grava bronze no S3 → Glue PySpark faz MERGE em tabelas Iceberg v2 (`b3_lakehouse_silver.b3_daily` e `bcb_daily`) no Glue Data Catalog → gold com dbt-athena rodando em tarefa ECS Fargate (imagem no ECR) → Athena. Documentação e evidências são escritas em português.

**Antes de agir, leia `docs/CONTINUIDADE.md`**: é o handoff oficial com ponto de parada, decisões encerradas, IDs de recursos, bloqueios de acesso e critérios de aceite das fases 4–6. O histórico 1986–2025 já está carregado — não recriar. Estados externos (AWS, variáveis do GitHub) devem ser reconsultados; evidências antigas não valem como leitura atual.

Os dados preparados e evidências locais (`local/`, ignorado pelo Git, ~5 GB) existem apenas no clone local original do proprietário (Windows), não em clones novos. Use o executável oficial da AWS CLI v2 com perfil `b3-dev`; `aws login` local tem falhado (HTTP 400), e o acesso confiável tem sido o CloudShell.

## Regras do projeto (do README)

- Toda operação com custo na AWS exige aprovação explícita do proprietário. O teto total do projeto é USD 10, com USD 2 de reserva (`scripts/cost_gate.py`). Budgets só alertam, não bloqueiam.
- Push somente com autorização por commit; PR e merge são feitos pelo proprietário. Trabalhar em branches com commits pequenos, nomes de branch sem prefixo `codex`.
- Plano da conta AWS é FREE: não converter a conta nem trocar tecnologia para contornar bloqueios (por isso o histórico roda em Glue, não EMR).
- Sem chaves AWS estáticas: localmente `aws login` (perfil `b3-dev`), no CI apenas OIDC.
- Proibido: NAT Gateway, MWAA, clusters fixos, RDS. Redshift Serverless desligado por padrão.
- Testes são offline: nenhuma chamada real à AWS ou à internet.
- Publicar em `docs/` só evidências verificadas, separando planejamento, implantação e validação. Não afirmar que algo foi carregado/implantado sem evidência.

## Comandos

```powershell
.\scripts\check-environment.ps1                 # verificação offline das ferramentas locais
python -m pip install -r scripts/requirements-ci.txt
python -m pytest tests -q                        # todos os testes
python -m pytest tests/test_silver.py::test_layout_precision_and_factor_not_silently_discarded   # um teste

# Artefatos (vão para artifacts/, ignorado pelo Git; Terraform os referencia)
python scripts/build_bronze.py                   # artifacts/bronze.zip (Lambda)
python scripts/build_silver.py                   # artifacts/silver-job.py + silver-libs.zip (Glue)
python -m pip install --only-binary=:all: --no-compile --target local/history-sdk -r scripts/requirements-history.txt
python scripts/build_history.py                  # artifacts/history-job.py, history-libs.zip, history-sdk.zip

# Terraform (mesmo que o CI; sem backend, sem AWS)
terraform fmt -check -recursive infra
terraform -chdir=infra/modules/silver init -backend=false -input=false -lockfile=readonly
terraform -chdir=infra/modules/silver validate
terraform -chdir=infra/modules/silver test       # testes mock em tests/*.tftest.hcl

# Gold offline: testes SQL (DuckDB + SQLGlot) e parse dbt sem AWS
python -m pip install -r scripts/requirements-gold-test.txt
python -m pytest tests/test_gold.py -q
# dbt parse exige GOLD_DATABASE, ATHENA_RESULTS_URI, GOLD_DATA_URI, ATHENA_WORKGROUP (valores fictícios bastam; ver ci.yml)
dbt parse --project-dir dbt --profiles-dir dbt --no-partial-parse
```

Ao rodar `terraform init -backend=false` num checkout que já tem `.terraform/` com backend S3, use um `TF_DATA_DIR` isolado; nunca apague estado nem reconfigure o backend para validar offline.

O CI (`.github/workflows/ci.yml`) roda pytest, os três builds e `init/validate/test` em `infra/bootstrap` e em cada `infra/modules/*` (Terraform 1.16.2, Python 3.11). `terraform plan`/`apply` de `infra/environments/dev` acontece apenas no workflow `infrastructure.yml`: plan em PR, apply do plano exato (criptografado com `scripts/plan_crypto.py`) após push em `main`, com aprovação no environment `aws-apply`. `workflow_dispatch` com `plan` não aplica, e mudar uma variável do GitHub (`ENABLE_GOLD`, `GOLD_IMAGE_DIGEST`, `BRONZE_SCHEDULE_ENABLED`) não dispara workflow. `infra/bootstrap` (state bucket, roles OIDC, permission boundaries) não é aplicado pelo CI. `gold-image.yml` publica a imagem dbt no ECR manualmente (confirmação `PUBLISH gold image`), sem executar RunTask.

## Arquitetura

### Fluxo de dados e controle de execução

Uma única tabela DynamoDB (`b3-lakehouse-aws-bronze-runs`, chave `pk`) controla todas as etapas, com chaves `bronze#<data>`, `silver#<data>`, `bronze#year=<ano>` e `history#<ano>`. Todo job segue o mesmo padrão: adquire lease condicional (`owner_id`, `lease_until`), grava `RUNNING`, e só marca `SUCCESS` após validação; falha grava `FAILED` + `error_type`. Uma etapa só avança se a anterior estiver `SUCCESS`, e as entradas são conferidas por SHA-256 contra o registrado no Dynamo.

- **Bronze diário** (`src/bronze/handler.py`): baixa o ZIP COTAHIST diário e as três séries BCB, valida tudo em memória (nunca extrai ZIP para disco, limites de tamanho, header/trailer, registros de 245 bytes) e grava em `bronze/source=<fonte>/reference_date=<data>/raw.{zip,json}` com `IfNoneMatch="*"` — objetos são imutáveis e reexecução é idempotente via metadados (`validated=v1`, `sha256`).
- **Silver diário** (`src/silver/job.py`, Glue 5.0): relê o bronze, confere hashes, faz parse e MERGE em Iceberg particionado por `months(trading_date)`, e então faz read-back (`exceptAll` nos dois sentidos) antes de gravar `SUCCESS`. Iceberg não tem transação entre as duas tabelas; a reexecução repara commit parcial.
- **Histórico** (um ano completo por execução, 1986–2025): `scripts/prepare_history.py --year ANO [--historical-contract]` baixa e valida localmente em `local/history-<ano>/` (gera `manifest.json`, `quote-audit.json`, `quarantine.jsonl`, `rate-coverage.json`) → `scripts/publish_history.py` envia ao S3 via AWS CLI (após aprovação) e grava `bronze#year=` por último → `src/history/job.py` roda no Glue (`--engine glue`) com MERGE nas mesmas tabelas silver. EMR Serverless está preparado (`infra/modules/history`, `scripts/history_request.py`) mas bloqueado na conta.

### Código compartilhado entre Lambda e Spark

`src/silver/transform.py` contém as funções puras de parse (`parse_quote`, `parse_rate`, `safe_identifier`) com posições do layout COTAHIST rev. 02 (2020); é usado pelo silver, pelo histórico e pela preparação local. Os scripts de build empacotam os mesmos arquivos com outros nomes: no Glue diário, `handler.py` vira `bronze_lib.py` e `transform.py` vira `silver_lib.py` (por isso `job.py` importa `bronze_lib`/`silver_lib`); no histórico, o módulo vai como `src/silver/transform.py`. Os builds são determinísticos (timestamps fixos, CRLF→LF) — mantenha isso ao alterar.

Escopo de dados: apenas `TPMERC=010` (à vista) com `CODBDI=02` (lote padrão). Preços são brutos (sem ajuste), mantendo `quotation_factor` e moeda original; taxas SGS 11/12 são percentuais ao dia; dólar antes de 07/1994 usa unidade `current_currency/USD`. Duplicatas exatas são removidas; duplicatas conflitantes de `(trading_date, ticker)` abortam o job.

### Gold (dbt)

`dbt/run.py` é o entrypoint do contêiner: primeiro roda os testes `tag:source_contract` sobre a silver (falha fechada), depois `dbt build --fail-fast`, com prazo total de 20 min e sem retries. Os modelos (dims, `fct_daily_quotes`, `mart_daily`, `mart_monthly`) são tabelas Iceberg **sem partição**, de propósito, para não estourar o limite de 100 partições do CTAS do Athena em 40 anos. O build não é atômico entre tabelas. `tests/test_gold.py` executa o SQL real dos modelos (renderizado com Jinja e traduzido de Trino para DuckDB via SQLGlot) sobre dados sintéticos; ao mudar um modelo, mantenha-o compatível com essa tradução.

### Terraform

`infra/environments/dev` é o único root implantado e liga módulos via flags com validações de dependência: `enable_bronze` → `enable_silver` → `enable_history` → `enable_history_glue` (este exige `history_emr_enabled = false`); `enable_gold` exige silver, e `gold_image_digest` fixa a imagem da task definition. Os defaults são todos desligados/seguros; os valores reais ficam em `terraform.tfvars` (ignorado). Cada módulo usa uma permissions boundary criada no bootstrap (`b3-lakehouse-aws-<componente>-boundary`) e tem testes `tests/*.tftest.hcl` que verificam restrições de segurança/custo (timeouts, concorrência 1, zero retries, sem agendamento). O job Glue histórico mantém o nome físico com "2025" para evitar substituição do recurso.
