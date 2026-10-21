# Continuidade e plano de conclusão

Referência: **21/10/2026**. Este documento permite continuar o projeto sem depender do histórico da conversa. Revalidar estados externos antes de agir; evidências antigas não equivalem a uma consulta atual.

## 1. Objetivo e ponto de parada

Entregar um pipeline real na AWS: B3/BCB → bronze → silver Iceberg → gold dbt/Athena, com execução em Fargate, orquestração Step Functions, qualidade, observabilidade, CI/CD e custo medido. O proprietário quer concluir todo o escopo principal, sem deixar o histórico para depois. O histórico completo já foi carregado; não recomeçar esse trabalho.

O código da fase 4 foi integrado no [PR #15](https://github.com/AbnerRidigolo/b3-lakehouse-aws/pull/15), merge `f22b5ab580cddaa801a8461e37c746b1c93c64cf`. Commits incluídos:

- `fb9585e`: evidências do histórico completo.
- `e00405d`: modelos gold, contratos, contêiner e testes.
- `b8fd402`: infraestrutura gold, permissões, workflows e estimativa.

O [CI 38327864068](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/38327864068) terminou SUCCESS, incluindo build Linux da imagem. O [workflow 38327864072](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/38327864072) terminou SUCCESS em plan e apply. O resumo detalhado do apply não foi recuperado via API de logs; não inferir quantidade de recursos alterados. As flags gold não estavam habilitadas, portanto esses resultados não comprovam implantação ou execução gold.

Últimas variáveis consultadas no GitHub:

| Variável | Valor observado | Consequência |
| --- | --- | --- |
| ENABLE_GOLD | true (21/10) | Infraestrutura gold implantada |
| GOLD_IMAGE_DIGEST | `sha256:d357906c…54fbac` (21/10) | Task definition `b3-lakehouse-aws-gold:2` fixa a imagem revisada |
| ENABLE_ORCHESTRATION | false | Fase 5 não implantada |
| BRONZE_SCHEDULE_ENABLED / ORCHESTRATION_SCHEDULE_ENABLED | false | Agendamento automático desligado |

**Ponto de parada em 21/10/2026:** fase 4 concluída na AWS. Gold implantada (PRs #19 e #20 corrigiram duas permissões do bootstrap, já aplicadas pelo proprietário), piloto Fargate com exit 0, 25/25 modelos e testes, reconciliação silver = gold e consultas de aceite registradas em [gold-evidence.md](gold-evidence.md). Custo estimado do piloto abaixo de USD 0,01, mais armazenamento.

**Próxima ação concreta:** preparar os pilotos da fase 5 (seção 6): revisar o bootstrap com `enable_orchestration_permissions=true`, o plano com `ENABLE_ORCHESTRATION=true` e a [estimativa](costs/orchestration.md), reler o gasto bruto e obter autorização específica. Não há autorização nova de custo implícita neste documento.

### Leitura de 20/10/2026 (somente APIs de controle, sem custo de processamento)

Feita com a identidade administrativa do proprietário em us-east-1; Cost Explorer não foi consultado (cobra por requisição).

| Item | Observado |
| --- | --- |
| Plano da conta | FREE, ACTIVE, expira em 02/12/2026; créditos restantes USD 131,02 (não descontados do teto) |
| Budget da conta (sem créditos, período 30/09–01/12) | gasto real USD 2,656; previsão USD 4,886; atualizado 20/10 12:53 UTC |
| Budget da tag Project | gasto real USD 1,622 (subconjunto do anterior; não somar) |
| `cost_gate.py --spent 2.656 --pending 0.10 --estimate 1.00` | dentro do teto; USD 4,24 restantes fora da reserva |
| Bootstrap gold | policies `gold-ci-*`, `gold-network-ci-*` e boundaries `gold-task`/`gold-execution` criadas em 13/10 e anexadas às roles OIDC; permissões de orquestração **não** aplicadas |
| `AWSServiceRoleForECS` | existe (não usar `create_ecs_service_role`) |
| Recursos gold/orquestração | nenhum: sem repositório ECR, cluster ECS, máquina de estados, SNS/SQS, alarmes ou painel; workgroup Athena só `primary` |
| Rede e serviços proibidos | sem NAT Gateway nem EIP; apenas a VPC padrão; EMR Serverless e Redshift Serverless retornam `SubscriptionRequiredException` |
| Bronze/silver | Lambda e schedule `b3-lakehouse-aws-bronze` (DISABLED); tabelas Iceberg `b3_daily`/`bcb_daily` atualizadas pela última vez em 09/10; último job histórico 2024 SUCCEEDED |
| `pipeline#published` no DynamoDB | ausente (nenhuma publicação orquestrada) |
| Variáveis GitHub (via log do plan) | `ENABLE_GOLD=true`, `GOLD_IMAGE_DIGEST` vazio, `ENABLE_ORCHESTRATION=false`, agendamentos false |

Plano do [PR #18](https://github.com/AbnerRidigolo/b3-lakehouse-aws/pull/18) ([run 39500538813](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/39500538813)): **21 a adicionar, 2 a alterar, 0 a destruir** — infraestrutura gold sem task definition (bucket, catálogo, workgroup, ECR, VPC/sub-rede/IGW sem NAT, cluster, roles, log group) mais o novo código da Lambda bronze e do `silver-libs.zip`. O run do merge em main ([39500553229](https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/39500553229)) aguarda aprovação de `aws-plan`; o apply exigirá depois a aprovação de `aws-apply`.

## 2. Regras do proprietário que continuam válidas

- Teto **total de USD 10**, com **USD 2 de reserva**; considerar consumo bruto e atraso do faturamento. Nunca descontar créditos para aparentar custo zero.
- Preservar plano FREE. Não converter conta, habilitar Organizations/Identity Center ou trocar tecnologia para contornar bloqueios sem aprovação.
- Antes de cada etapa com custo, apresentar estimativa e obter autorização. Uma autorização de push não autoriza executar workloads pagos.
- Ao final de cada fase, mostrar resultado e custo e aguardar aprovação da fase seguinte.
- Trabalhar em branches com commits pequenos, **sem prefixo codex**. Cada push depende de autorização para os commits concretos. O proprietário abre e integra os PRs.
- Usar credenciais temporárias e MFA; não pedir ou registrar senhas, access keys ou códigos de login no chat/repositório. Nenhum segredo deve constar deste handoff.
- Não criar NAT Gateway, MWAA, RDS ou clusters permanentes. Manter agendamento desligado até aprovação explícita.
- Não repetir aprovações já concedidas para o mesmo ato; consultar o contexto disponível. Não transformar uma aprovação antiga em autorização para uma nova cobrança.
- README deve separar implementado, testado offline e validado na AWS. Testes automatizados não acessam AWS/internet; execuções reais são pilotos operacionais separados e autorizados.

## 3. Acesso, ambiente e arquivos locais

- Repositório: `https://github.com/AbnerRidigolo/b3-lakehouse-aws`.
- Checkout usado: o clone local original do proprietário, no Windows (único com a pasta `local/`).
- Região: `us-east-1`. Conta esperada: a do projeto (confirmar com `aws sts get-caller-identity`; o ID não é versionado), usuário IAM administrativo do proprietário.
- AWS CLI: executável oficial da AWS CLI v2 no Windows, perfil `b3-dev`. O wrapper `aws` do PATH apresentou problema; preferir o executável oficial.
- O fluxo `aws login` apresentou HTTP 400 na autorização OAuth, inclusive após novas tentativas. Login direto no console funcionou, e o usuário executou `aws sts get-caller-identity` no **CloudShell us-east-1**, confirmando a conta/identidade acima.
- Login no console/CloudShell **não autentica automaticamente o CLI local**. Não insistir em URLs OAuth antigas nem transferir credenciais para arquivos. Reconfirmar a sessão temporária antes de operar.
- Docker Desktop local não disponibilizou o engine Linux. O CI conseguiu construir a imagem; isso removeu a pendência de build, mas não publicou a imagem no ECR.
- GitHub CLI `gh` não foi utilizado; git e API autenticada foram usados. Nunca imprimir a saída de `git credential fill` ou gravar tokens. Há ambientes protegidos `aws-plan` e `aws-apply`.
- `local/`, `artifacts/`, estados, tfvars e dados são ignorados pelo Git. Um clone novo não contém esses arquivos. Não copiar `.aws`, `.env`, estados, planos ou configurações sensíveis para uma conversa ou repositório público.

Evidências locais úteis, se o próximo agente continuar nesta máquina:

| Caminho | Conteúdo |
| --- | --- |
| local/batch-1995-2024/ | Status Glue e verificação dos snapshots de cada ano |
| local/batch-1987-1994/ | Evidências do lote anterior |
| local/history-1986-evidence.json | Carga inicial histórica e quarentena |
| local/history-YYYY/ | Fontes e manifestos locais dos anos preparados |
| local/full-history-preflight.json | Conferência local dos 40 anos |
| local/history-sdk/ | Dependências boto3 isoladas para scripts históricos |
| local/gold-venv/ | dbt-core 1.12.5 e dbt-athena 1.11.1 usados no parse local |
| local/gold-test/ | DuckDB, SQLGlot e Jinja para testes locais |

O agente em outra máquina deve usar as evidências resumidas versionadas e coletar novas leituras autorizadas da AWS quando necessário. Não reconstruir segredos ou estados a partir de suposições.

## 4. Dados e decisões já encerradas

- Histórico **1986–2025**, 40 anos completos, concluído em 08/10/2026; mais o incremental de 01/10/2026.
- Totais registrados: **3.185.477 cotações**, **29.917 taxas**, **374 linhas em quarentena**. 2026 não está completo nem atualizado diariamente.
- Escopo das cotações: BDI 02, mercado 010. Preservar layout oficial e fonte original.
- EMR Serverless retornou bloqueio de habilitação da conta; o proprietário autorizou **Glue para todo o histórico**. Não tentar upgrade da conta para recriar EMR.
- Job histórico mantém o nome `b3-lakehouse-aws-history-2025-glue`, apesar de suportar os demais anos; não renomear recursos sem analisar impacto.
- Quarentena de linhas inválidas e lacunas explícitas do BCB foram aprovadas. Não preencher CDI nem descartar o ano inteiro por essas exceções conhecidas.
- As moedas anteriores ao Real e a unidade `current_currency/USD` são intencionais. Não tratar todo o histórico como BRL.
- A repetição do incremental foi validada. Não declarar idempotência anual demonstrada: o backfill histórico não foi repetido.

Recursos de referência para leituras, sem recriá-los:

- S3 bronze: `b3-lakehouse-aws-bronze-<ACCOUNT_ID>`.
- S3 silver: `b3-lakehouse-aws-silver-<ACCOUNT_ID>`.
- Estado Terraform: `b3-lakehouse-aws-<ACCOUNT_ID>-state`, chave dev `dev/terraform.tfstate`.
- DynamoDB: `b3-lakehouse-aws-bronze-runs`.
- Glue Database: `b3_lakehouse_silver`, tabelas `b3_daily` e `bcb_daily`.

As estimativas de computação dos lotes não são o faturamento total. O lote 1995–2024 estimou USD 1,14999 de Glue; não usar esse valor sozinho como gasto acumulado. Consultar [evidências completas](history-complete-evidence.md) e billing atualizado.

## 5. Fase 4 — concluir gold de verdade

### A. Conferir acesso, custo e elegibilidade

1. Confirmar branch/commit, árvore de trabalho e estado remoto antes de editar. Preservar alterações do usuário.
2. No CloudShell, obter checkout do commit revisado e executar `EXPECTED_ACCOUNT=<ID da conta> python scripts/gold_preflight.py` (o script recusa conta diferente ou variável ausente). Conferir antes se boto3/botocore e a API `get_account_plan_state` estão disponíveis; se não estiverem, usar a CLI oficial ou dependências isoladas, sem registrar credenciais.
3. O preflight consulta identidade, plano, budgets, service-linked role ECS, clusters e repositório ECR. Erros de permissão ou API não comprovam ausência de recurso. Uma listagem de ECS não comprova que o FREE permite executar Fargate.
4. Obter gasto bruto atualizado, intervalo coberto e atraso de atualização. Os budgets da conta e do projeto podem cobrir o mesmo consumo; **não somá-los**. Preservar a tag Project e verificar sua ativação para alocação de custos, sem afirmar que já está ativa.
5. Aplicar `scripts/cost_gate.py` com valores reais de gasto, pendências e estimativa. Reserva proposta: **USD 1** para publicação/infraestrutura/uma execução, detalhada em [costs/gold.md](costs/gold.md). A estimativa não é aprovação nem bloqueio automático de gasto.

### B. Implantar permissões e infraestrutura

1. Após aprovação de custo, revisar bootstrap com `enable_gold_permissions=true`; preservar todas as flags existentes. Não substituir tfvars reais por exemplos.
2. Confirmar se `AWSServiceRoleForECS` existe. Usar `create_ecs_service_role=true` somente se realmente ausente; não tentar duplicá-lo. Revisar o plano antes de aplicar.
3. Habilitar `ENABLE_GOLD=true`, inicialmente sem digest. Revisar o plano para bucket, catálogo, workgroup, ECR, rede, cluster e roles; nenhuma remoção de bronze/silver é esperada.
4. O workflow `infrastructure.yml` aplica em push na main ou por `workflow_dispatch` na main com operação `apply` e confirmação `APPLY b3-lakehouse-aws`, sempre com aprovação `aws-apply`; a operação `plan` **não aplica**. Alterar uma variável do GitHub não dispara workflow: depois de mudá-la, disparar `apply` manualmente e revisar o plano antes de aprovar. Evitar commits vazios.
5. Se o plano incluir mudanças inesperadas ou o FREE bloquear um serviço, interromper a implantação e esclarecer a causa. Não remover boundaries nem ampliar permissões indiscriminadamente.

### C. Publicar e executar o contêiner

1. Disparar `gold-image.yml` na main com a confirmação `PUBLISH gold image` e aprovação no ambiente exigido. A imagem construída no CI anterior não foi preservada/publicada por esse CI; o workflow de publicação constrói novamente.
2. Conferir tamanho, tag de commit e digest resultante no ECR. Atualizar a estimativa se a imagem exceder a hipótese de 1 GB. Definir `GOLD_IMAGE_DIGEST` com o digest revisado.
3. Gerar/aplicar novo plano da task definition. Conferir 0,5 vCPU/1 GiB, roles, logs, rede pública com IP atribuído à tarefa e ausência de NAT/serviço ECS permanente.
4. Executar **uma** tarefa com os outputs `gold_cluster_arn`, `gold_task_definition_arn` e `gold_network_configuration`. Não inventar IDs de subnet/security group nem conceder RunTask ao CI apenas por conveniência.
5. Registrar task ARN, horários, imagem/digest, exit code, resultado de cada modelo/teste, bytes Athena e custo estimado/observado. Em falha, parar e diagnosticar; não repetir automaticamente.
6. O timeout interno dbt é 20 minutos, mas não inclui provisionamento/pull e não garante cancelamento de consultas já submetidas. Acompanhar a tarefa e encerrar consultas remanescentes do próprio piloto quando necessário, preservando outras execuções.

### D. Aceite da fase 4

- [x] Tarefa real termina com exit code 0; contratos de origem e `dbt build` passam.
- [x] Seis tabelas gold Iceberg existem e são consultáveis no workgroup dedicado.
- [x] Fato e mart diário reconciliam com a silver; dimensões e chaves passam nos testes.
- [x] Amostras demonstram moedas históricas, lacunas, quarentena na origem e eventos suspeitos tratados corretamente.
- [x] Consultas de `docs/gold-queries.sql` executadas, com resultados e bytes registrados.
- [x] Não restam tarefas/consultas do piloto em execução; gasto e armazenamento remanescente documentados.
- [x] README atualizado com evidências reais, incluindo limitações ou falhas encontradas.

**Cuidados de implementação:** dbt reconstrói seis modelos sem partição para evitar o limite de 100 partições CTAS em 40 anos. O build não é atômico entre tabelas: falhas podem deixar resultados parciais. Não publicar sucesso sem todos os testes. Não executar gold simultaneamente com outra gold ou escrita silver sem coordenação. Consulte [phase-4.md](phase-4.md) para a semântica de retornos e limitações do calendário.

## 6. Fase 5 — pipeline completo e confiabilidade

Preparar código, testes offline e estimativa antes de pedir aprovação da implantação desta fase.

**Preparado em 20/10/2026, ainda não implantado:** código, Terraform, testes offline e estimativa dos itens 1–7 estão descritos em [phase-5.md](phase-5.md), com [estimativa](costs/orchestration.md) e [comandos de operação](operacao.md). Faltam os pilotos reais (item 8), que dependem do aceite da fase 4 e de aprovação de custo.

1. Implementar Step Functions para bronze → Glue incremental → ECS/dbt, com parâmetros de data explícitos e espera pela conclusão de cada etapa.
2. Reusar contratos e controles existentes; não criar uma segunda implementação dos parsers. Registrar no DynamoDB etapa, referência, estado, contagens, falhas e resultado de qualidade; definir lease/concorrência e recuperação de execução interrompida.
3. Proteger reprocessamento: repetir a mesma data não duplica dados nem dispara tarefas concorrentes; uma falha só retoma etapas necessárias. Diferenciar retry de erro transitório de retry de contrato/dado inválido. Definir tentativas e timeout globais compatíveis com o orçamento.
4. Projetar a publicação gold para não apresentar conjunto parcialmente atualizado como carga concluída. O status de execução ajuda a operação, mas consumidores SQL diretos também precisam de contrato claro de acesso/versão ou outra barreira efetiva. Revisar essa decisão antes de declarar publicação consistente.
5. Criar tratamento de falha com SQS/DLQ e SNS, sem expor dados sensíveis. Usar o e-mail já configurado no projeto; não gravá-lo em documentação pública. A assinatura SNS pode exigir confirmação manual do proprietário.
6. Adicionar alarmes e painel CloudWatch: falhas/duração, qualidade, ausência de carga esperada quando o agendamento estiver ativo, DLQ e consumo relevante. Retenção curta; incluir custos de alarmes/painel na estimativa.
7. Conectar Scheduler à máquina de estados. Dias úteis de calendário não garantem pregão: definir resultado explícito para feriado/fonte ainda indisponível, sem confundir dia sem negociação com carga vazia válida. Permanecer DISABLED até autorização específica de recorrência e custo.
8. Testar offline o fluxo e IAM; depois pilotos reais aprovados de sucesso, repetição e falha controlada/recuperação. Não corromper ou apagar o histórico de produção para simular falhas.

Aceite: execução ponta a ponta comprovada; repetição sem duplicação; falha bloqueia etapas dependentes; alerta/DLQ funcionam; recuperação rastreável; nenhuma tarefa órfã; custo registrado. A aprovação para um piloto não autoriza agendamento diário indefinido.

## 7. Fase 6 — evidências e encerramento

- [ ] Diagrama final corresponde aos recursos realmente implantados, incluindo a decisão Glue/EMR e Step Functions/MWAA.
- [ ] Prints sem segredos e links de execuções, consultas e verificações de qualidade disponíveis.
- [ ] Custo real por serviço e tag Project, com período, data de atualização e limitações de atribuição. Separar consumo bruto, créditos e estimativas; nunca apresentar estimativa como fatura.
- [ ] Instruções para executar uma data, reprocessar falha, interpretar quarentena/lacunas, consultar gold e interromper operação.
- [ ] Decisão explícita sobre retenção e scheduler. Alertas de orçamento não garantem teto de USD 10; recorrência precisa de horizonte e mecanismo de parada revisados.
- [ ] Plano de encerramento revisável: parar tarefas/agendamento, decidir retenção dos dados/imagens, limpar recursos autorizados e preservar estado/evidências. Não usar force_destroy para contornar proteção de dados.
- [ ] README sem alegações de ajuste por eventos corporativos, atualização diária ativa ou custo final ainda não demonstradas.

Redshift é opcional, desligado e fora do caminho crítico. Só iniciar com pedido e estimativa próprios.

## 8. Validação e mapa para o próximo agente

Principais entradas:

| Arquivo/pasta | Para que consultar |
| --- | --- |
| src/bronze/, src/silver/, src/history/ | Contratos de ingestão/processamento existentes |
| dbt/models/, dbt/tests/, dbt/run.py | Semântica gold, testes e execução com gate de origem |
| infra/modules/gold/ | Infraestrutura e templates de política do runtime |
| infra/bootstrap/gold-ci.tf | Permissões CI, boundaries e service-linked role opcional |
| infra/environments/dev/gold.tf | Flags e outputs gold |
| .github/workflows/infrastructure.yml | Gatilhos reais de plan/apply e aprovação |
| .github/workflows/gold-image.yml | Publicação manual da imagem, sem RunTask |
| scripts/gold_preflight.py, scripts/cost_gate.py | Leituras de prontidão e cálculo do teto |
| docs/history-complete-evidence.md | Histórico concluído e limitações das evidências |

Na última validação: **48 testes e 24 subtestes Python**, `dbt parse` e **sete testes Terraform** (cinco bootstrap, dois gold) passaram localmente. O CI integrado também passou, incluindo a imagem Linux. Testes SQL usam DuckDB/SQLGlot; nenhuma execução gold na AWS foi demonstrada ainda.

Em clone novo, instalar dependências em ambiente isolado e seguir `.github/workflows/ci.yml`. Gerar pacotes necessários pelos scripts antes de validar módulos que usam `filesha256`. Para `terraform init -backend=false`, usar `TF_DATA_DIR` limpo/isolado: o cache local existente tentou reutilizar backend S3 e exigiu credenciais expiradas. **Não apagar estado nem reconfigurar backend para resolver uma validação offline.**

## 9. Texto para iniciar a próxima conversa

> Continue o projeto b3-lakehouse-aws a partir de README.md e docs/CONTINUIDADE.md. Bronze/silver e histórico 1986–2025 já estão carregados; não os recrie. A gold está implantada e validada na AWS (docs/gold-evidence.md); a orquestração está preparada, mas não implantada. Comece verificando o estado atual do GitHub, o acesso temporário via CloudShell e o consumo real. Prepare e revise os pilotos da orquestração antes de pedir autorização de custo. Preserve o plano FREE e o teto total de USD 10, incluindo USD 2 de reserva. Cada push precisa de autorização por commit; eu abro e integro os PRs. Conclua depois a orquestração, confiabilidade e evidências, respeitando as aprovações de fase. Não solicite ou registre credenciais e não trate este texto como autorização de gasto, push ou ativação de agendamento.
