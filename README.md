# B3 Lakehouse AWS

Lakehouse de dados de mercado com fontes reais da B3 e do Banco Central, ingestão em Python, processamento Spark, tabelas Apache Iceberg e infraestrutura como código na AWS.

**Estado verificado em 12/10/2026:** bronze e silver implantadas em `us-east-1`; histórico completo de **1986–2025** carregado, além do incremental de **01/10/2026**. A gold tem código integrado e imagem construída no CI, mas ainda não foi implantada nem executada na AWS. O agendamento permanece desligado.

> **Continuidade do projeto:** leia o [plano de conclusão e passagem para outro agente](docs/CONTINUIDADE.md). Ele registra o ponto de parada, as decisões já tomadas, os bloqueios, a sequência de implantação e os critérios para encerrar cada etapa.

## Resultados já demonstrados

- **3.185.477 cotações e 29.917 taxas** nas tabelas silver, segundo as evidências salvas na conclusão das cargas.
- **40 anos completos (1986–2025)** processados; o ano de 2026 não está completo.
- **374 registros em quarentena**, preservando rastreabilidade; dados brutos mantidos na bronze.
- Ingestão e MERGE incremental com repetição validada. A repetição do backfill anual ainda não foi testada.
- Infraestrutura Terraform, CI/CD no GitHub Actions, autenticação OIDC e ambientes protegidos para plan/apply.
- Modelagem gold com testes para moedas históricas, fator de cotação, lacunas do CDI e possíveis eventos corporativos.

As contagens vêm das [evidências do histórico](docs/history-complete-evidence.md); não representam uma nova consulta em tempo real à AWS.

## O que está pronto e o que falta

| Componente | Estado confirmado |
| --- | --- |
| Bootstrap, estado remoto, budgets e OIDC | Implantados e validados |
| Lambda, S3 bronze e controle DynamoDB | Implantados; carga real e idempotência verificadas |
| Glue PySpark e silver Iceberg | Implantados; incremental e histórico completo validados |
| EMR Serverless | Criação bloqueada pela habilitação da conta; não executado |
| Substituição do backfill por Glue | Autorizada pelo proprietário e executada para preservar o plano FREE |
| dbt gold: dimensões, fato e marts | Código integrado na main; testes offline aprovados |
| Imagem Docker gold | Construída com sucesso no CI; publicação no ECR pendente |
| ECR, Fargate, catálogo e workgroup gold | Terraform preparado, implantação desativada |
| Step Functions ponta a ponta | Ainda não implementado/implantado |
| SQS, SNS, alarmes e painel completos | Ainda pendentes como solução integrada |
| Scheduler | Criado para bronze, desativado; falta conectar a orquestração final |
| Evidências finais e custo real por serviço | Pendentes de consolidação |
| Redshift Serverless | Opcional; não é requisito para concluir o escopo principal |

O [CI do PR #15](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/38327864068) concluiu com sucesso, incluindo testes, dbt parse, build Linux da imagem e validação Terraform. O [workflow de infraestrutura](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/38327864072) também terminou com plan/apply bem-sucedidos. **Isso não significa que a gold foi implantada:** `ENABLE_GOLD` e `GOLD_IMAGE_DIGEST` estavam ausentes na última consulta às variáveis do repositório.

## Arquitetura

| Camada | Implementação e propósito |
| --- | --- |
| Bronze | Lambda Python → S3, com fontes originais, manifestos e controle de ingestão |
| Silver | Glue PySpark → Iceberg/S3 + Glue Data Catalog; parsing, tipagem, deduplicação e MERGE |
| Gold, preparada | dbt-Athena em ECS Fargate, com imagem ECR; dimensões, fato e marts Iceberg |
| Orquestração, planejada | EventBridge Scheduler → Step Functions → bronze → silver → gold |
| Confiabilidade, a concluir | DynamoDB, SQS, SNS e CloudWatch para controle, falhas e acompanhamento |
| Plataforma | Terraform e GitHub Actions com OIDC, plan revisado e apply protegido |

Fargate usará sub-rede pública com IP público apenas durante a tarefa, sem NAT Gateway ou serviço permanente. Step Functions foi escolhido para coordenar execuções sob demanda, evitando manter um ambiente MWAA cobrado por hora. O histórico foi executado com Glue após o bloqueio do EMR; a mudança foi explicitamente autorizada.

## Fontes e contrato dos dados

- **B3 COTAHIST:** registros de largura fixa de 245 bytes; escopo BDI `02` e mercado `010`. O layout oficial orienta o parser. [Implementação e validações silver](docs/phase-3.md).
- **BCB SGS:** CDI, Selic e câmbio de venda; unidades originais preservadas, com lacunas registradas explicitamente.
- Preços B3 **não são ajustados por proventos ou desdobramentos**. Moedas antigas e fatores de cotação não podem ser ignorados.
- A gold preparada normaliza preço por fator de cotação, bloqueia comparações incompatíveis e sinaliza variações extremas como possíveis eventos, sem afirmar que são eventos confirmados.
- Comparações com CDI exigem cobertura conforme o contrato documentado; ausências não são preenchidas com valores inventados. O calendário observado não substitui um calendário oficial de feriados bancários/da bolsa.

Consulte a [semântica dos modelos gold e suas limitações](docs/phase-4.md).

## Plano para terminar

1. **Implantar e validar a gold.** Conferir acesso, plano FREE e gasto atualizado; aprovar a estimativa; implantar permissões e infraestrutura; publicar a imagem; executar uma tarefa dbt e conferir testes, contagens, consultas e custo real.
2. **Concluir a orquestração e a confiabilidade.** Implementar Step Functions, controle de execução, retentativas limitadas, desvio de erro, SQS, SNS, alarmes e painel. Testar sucesso, repetição da mesma data, falha e recuperação. Manter o scheduler desligado até aprovação específica.
3. **Encerrar com evidências reproduzíveis.** Atualizar diagramas e prints, registrar consultas reais e custos por serviço/tag, documentar operação, reprocessamento e encerramento. Não declarar o projeto concluído enquanto faltarem os testes ponta a ponta.

A sequência operacional e os critérios de aceite estão em [CONTINUIDADE.md](docs/CONTINUIDADE.md). Não é necessário repetir o histórico nem recriar a infraestrutura já validada para avançar.

## Custo e regras de operação

- **Teto total: USD 10**, incluindo **USD 2 reservados** para atraso do faturamento e encerramento. Não é um teto mensal; créditos promocionais não anulam o consumo bruto.
- O primeiro piloto gold tem [reserva proposta de USD 1](docs/costs/gold.md), **ainda sem autorização específica de execução**. O gasto real atualizado precisa ser consultado antes de liberar a etapa.
- Budgets alerta, mas não bloqueia gastos. O workgroup gold preparado limita bytes por consulta, não o gasto agregado.
- Aprovação antes de operações com custo e ao final de cada fase. Push exige autorização para cada commit; PR e merge são feitos pelo proprietário.
- Preservar plano FREE; não habilitar Organizations/Identity Center nem converter o plano para contornar restrições.
- Sem NAT Gateway, MWAA, clusters fixos ou RDS. Redshift somente se solicitado e aprovado separadamente.
- Credenciais temporárias: OIDC no CI; acesso IAM/CloudShell para operação. Não solicitar, gravar ou publicar senhas, tokens ou chaves estáticas.
- Não publicar como realizado aquilo que só está implementado ou simulado.

## Estrutura do repositório

```text
infra/bootstrap/        Estado remoto, papéis CI e boundaries
infra/modules/          Fundação e módulos bronze, silver, histórico e gold
infra/environments/dev/ Composição e flags de implantação
src/                    Ingestão e processamento Python/Spark
dbt/                    Modelos gold, contratos e contêiner
scripts/                Empacotamento, preparação, preflight e controle de custo
tests/                  Testes offline
.github/workflows/      CI, infraestrutura, OIDC e publicação manual de imagem
docs/                   Evidências, decisões, custos e plano de conclusão
local/                  Evidências brutas e ferramentas locais; ignorado pelo Git
```

## Validação local sem AWS

Em um ambiente virtual Python 3.11:

```powershell
python -m pip install -r scripts/requirements-ci.txt
python -m pytest tests -q
.\scripts\check-environment.ps1
```

A instalação requer internet; os testes não chamam AWS nem fontes externas. O CI também valida dbt, constrói a imagem e executa testes Terraform com provider simulado. A suíte local registrada tem **48 testes e 24 subtestes**. Modelos SQL são exercitados com dados sintéticos em DuckDB após tradução de Trino; isso não substitui o piloto Athena/Iceberg real.

## Evidências e referências do projeto

- [Fundação e consumo observado](docs/foundation-validation.md)
- [Primeira carga bronze](docs/bronze-data-evidence.md)
- [Silver incremental e repetição](docs/silver-data-evidence.md)
- [Bloqueio do EMR](docs/emr-subscription-block.md) e [alternativa Glue autorizada](docs/history-glue.md)
- [Histórico consolidado](docs/history-complete-evidence.md)
- [Gold: modelos e implantação](docs/phase-4.md), [estimativa](docs/costs/gold.md) e [consultas ainda a executar](docs/gold-queries.sql)
- **[Passagem para o próximo agente e plano de conclusão](docs/CONTINUIDADE.md)**
