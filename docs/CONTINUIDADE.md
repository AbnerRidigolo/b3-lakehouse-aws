# Continuidade e plano de conclusão

Referência: **12/10/2026**. Este documento permite continuar o projeto sem depender do histórico da conversa. Revalidar estados externos antes de agir; evidências antigas não equivalem a uma consulta atual.

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
| ENABLE_GOLD | Ausente | Terraform recebe false |
| GOLD_IMAGE_DIGEST | Ausente | Não há digest revisado configurado |
| BRONZE_SCHEDULE_ENABLED | false | Agendamento automático desligado |

**Próxima ação concreta:** consultar preflight/custos no CloudShell, revisar a reserva do piloto gold e obter autorização específica antes de implantar ou executar. Não há autorização nova de custo implícita neste documento.

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
- Checkout usado: `C:/Users/Abner/OneDrive/Desktop/projetos-eng/b3-lakehouse-aws`.
- Região: `us-east-1`. Conta esperada: `259081046223`, IAM `abner-admin`.
- AWS CLI: `C:/Program Files/Amazon/AWSCLIV2/aws.exe`, perfil `b3-dev`. O wrapper `aws` do PATH apresentou problema; preferir o executável oficial.
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

- S3 bronze: `b3-lakehouse-aws-bronze-259081046223`.
- S3 silver: `b3-lakehouse-aws-silver-259081046223`.
- Estado Terraform: `b3-lakehouse-aws-259081046223-state`, chave dev `dev/terraform.tfstate`.
- DynamoDB: `b3-lakehouse-aws-bronze-runs`.
- Glue Database: `b3_lakehouse_silver`, tabelas `b3_daily` e `bcb_daily`.

As estimativas de computação dos lotes não são o faturamento total. O lote 1995–2024 estimou USD 1,14999 de Glue; não usar esse valor sozinho como gasto acumulado. Consultar [evidências completas](history-complete-evidence.md) e billing atualizado.

## 5. Fase 4 — concluir gold de verdade

### A. Conferir acesso, custo e elegibilidade

1. Confirmar branch/commit, árvore de trabalho e estado remoto antes de editar. Preservar alterações do usuário.
2. No CloudShell, obter checkout do commit revisado e executar `python scripts/gold_preflight.py`. Conferir antes se boto3/botocore e a API `get_account_plan` estão disponíveis; se não estiverem, usar a CLI oficial ou dependências isoladas, sem registrar credenciais.
3. O preflight consulta identidade, plano, budgets, service-linked role ECS, clusters e repositório ECR. Erros de permissão ou API não comprovam ausência de recurso. Uma listagem de ECS não comprova que o FREE permite executar Fargate.
4. Obter gasto bruto atualizado, intervalo coberto e atraso de atualização. Os budgets da conta e do projeto podem cobrir o mesmo consumo; **não somá-los**. Preservar a tag Project e verificar sua ativação para alocação de custos, sem afirmar que já está ativa.
5. Aplicar `scripts/cost_gate.py` com valores reais de gasto, pendências e estimativa. Reserva proposta: **USD 1** para publicação/infraestrutura/uma execução, detalhada em [costs/gold.md](costs/gold.md). A estimativa não é aprovação nem bloqueio automático de gasto.

### B. Implantar permissões e infraestrutura

1. Após aprovação de custo, revisar bootstrap com `enable_gold_permissions=true`; preservar todas as flags existentes. Não substituir tfvars reais por exemplos.
2. Confirmar se `AWSServiceRoleForECS` existe. Usar `create_ecs_service_role=true` somente se realmente ausente; não tentar duplicá-lo. Revisar o plano antes de aplicar.
3. Habilitar `ENABLE_GOLD=true`, inicialmente sem digest. Revisar o plano para bucket, catálogo, workgroup, ECR, rede, cluster e roles; nenhuma remoção de bronze/silver é esperada.
4. O workflow `infrastructure.yml` aplica em push na main; `workflow_dispatch` com operação plan **não aplica**. Alterar uma variável do GitHub tampouco dispara workflow automaticamente. Preparar uma mudança revisada em main ou aplicar explicitamente o plano revisado pelo operador. Evitar commits vazios e ciclos de aprovação sem mudança concreta.
5. Se o plano incluir mudanças inesperadas ou o FREE bloquear um serviço, interromper a implantação e esclarecer a causa. Não remover boundaries nem ampliar permissões indiscriminadamente.

### C. Publicar e executar o contêiner

1. Disparar `gold-image.yml` na main com a confirmação `PUBLISH gold image` e aprovação no ambiente exigido. A imagem construída no CI anterior não foi preservada/publicada por esse CI; o workflow de publicação constrói novamente.
2. Conferir tamanho, tag de commit e digest resultante no ECR. Atualizar a estimativa se a imagem exceder a hipótese de 1 GB. Definir `GOLD_IMAGE_DIGEST` com o digest revisado.
3. Gerar/aplicar novo plano da task definition. Conferir 0,5 vCPU/1 GiB, roles, logs, rede pública com IP atribuído à tarefa e ausência de NAT/serviço ECS permanente.
4. Executar **uma** tarefa com os outputs `gold_cluster_arn`, `gold_task_definition_arn` e `gold_network_configuration`. Não inventar IDs de subnet/security group nem conceder RunTask ao CI apenas por conveniência.
5. Registrar task ARN, horários, imagem/digest, exit code, resultado de cada modelo/teste, bytes Athena e custo estimado/observado. Em falha, parar e diagnosticar; não repetir automaticamente.
6. O timeout interno dbt é 20 minutos, mas não inclui provisionamento/pull e não garante cancelamento de consultas já submetidas. Acompanhar a tarefa e encerrar consultas remanescentes do próprio piloto quando necessário, preservando outras execuções.

### D. Aceite da fase 4

- [ ] Tarefa real termina com exit code 0; contratos de origem e `dbt build` passam.
- [ ] Seis tabelas gold Iceberg existem e são consultáveis no workgroup dedicado.
- [ ] Fato e mart diário reconciliam com a silver; dimensões e chaves passam nos testes.
- [ ] Amostras demonstram moedas históricas, lacunas, quarentena na origem e eventos suspeitos tratados corretamente.
- [ ] Consultas de `docs/gold-queries.sql` executadas, com resultados e bytes registrados.
- [ ] Não restam tarefas/consultas do piloto em execução; gasto e armazenamento remanescente documentados.
- [ ] README atualizado com evidências reais, incluindo limitações ou falhas encontradas.

**Cuidados de implementação:** dbt reconstrói seis modelos sem partição para evitar o limite de 100 partições CTAS em 40 anos. O build não é atômico entre tabelas: falhas podem deixar resultados parciais. Não publicar sucesso sem todos os testes. Não executar gold simultaneamente com outra gold ou escrita silver sem coordenação. Consulte [phase-4.md](phase-4.md) para a semântica de retornos e limitações do calendário.

## 6. Fase 5 — pipeline completo e confiabilidade

Preparar código, testes offline e estimativa antes de pedir aprovação da implantação desta fase.

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

> Continue o projeto b3-lakehouse-aws a partir de README.md e docs/CONTINUIDADE.md. Bronze/silver e histórico 1986–2025 já estão carregados; não os recrie. A gold está integrada e validada no CI, mas desativada e ainda não executada na AWS. Comece verificando o estado atual do GitHub, o acesso temporário via CloudShell e o consumo real. Prepare e revise o piloto gold antes de pedir autorização de custo. Preserve o plano FREE e o teto total de USD 10, incluindo USD 2 de reserva. Cada push precisa de autorização por commit; eu abro e integro os PRs. Conclua depois a orquestração, confiabilidade e evidências, respeitando as aprovações de fase. Não solicite ou registre credenciais e não trate este texto como autorização de gasto, push ou ativação de agendamento.
