# Fundação: validações em 01/10/2026

## Verificado

- PRs #1, #2 e #3 mesclados pelo proprietário; CI offline passou na main.
- Identidade OIDC dos papéis plan e apply confirmada após aprovação dos environments.
- Confiança IAM corrigida para os IDs imutáveis do proprietário e do repositório.
- Secret TF_PLAN_ENCRYPTION_KEY cadastrado; conteúdo nunca publicado.
- DEPLOY_ENABLED habilitado com autorização para teste do plano.
- Execução manual https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/36923074862 concluída: plan passou e informou nenhuma alteração necessária. Backend remoto acessado e validação Terraform concluída.
- Artifact reviewed-plan-encrypted gerado (7.326 bytes), com expiração em 02/10/2026 às 20:39:53 UTC. O job apply foi ignorado nessa execução, conforme condição do workflow.
- Tag de alocação Project ativada; API confirmou Status Active às 20:42:19 UTC. Disponibilidade dos custos filtrados ainda pode ter atraso.

## Consumo observado

Consulta aos budgets em 01/10/2026, sem chamadas a GetCostAndUsage:

| Budget | Consumo informado | Atualização do cálculo (São Paulo) |
| --- | ---: | --- |
| Toda a conta | USD 0,047 | 01/10/2026 16:17:31 |
| Project=b3-lakehouse-aws | USD 0,00 | 01/10/2026 16:17:50 |

Os cálculos excluem créditos e reembolsos. O valor da conta pode incluir outros projetos e serve como referência conservadora. O budget filtrado ainda foi calculado antes da ativação da tag; zero não comprova ausência de consumo. Gastos recentes ou ainda não faturados podem estar ausentes. A previsão automática da conta retornou USD 3,271; não é gasto realizado nem estimativa validada para as próximas fases.

Teto total USD 10; reserva USD 2. Antes de cada implantação, somar consumo conhecido, consumo pendente estimado e próxima operação. Não usar ausência de alerta como autorização de gasto.

## Próxima validação

Publicar esta atualização mediante autorização por commit; proprietário abre e mescla o PR. Como DEPLOY_ENABLED está true, o push resultante na main inicia plan e, após seu sucesso, apply, cada um com aprovação do environment. A mudança deste documento não altera infraestrutura; espera-se novamente um plano sem alterações, a confirmar no run.

Reservar até USD 0,01 adicional para requisições S3 dessa validação, sujeito à autorização do proprietário antes da execução. Revisar o plano antes de aprovar aws-apply. Essa execução validará download, autenticação e decifragem do artifact, aplicação do mesmo plano e permissões de acesso ao estado. Se surgirem alterações inesperadas, não aprovar apply.

Encerramento da fase 1 ainda pendente dessa validação integrada. Recebimento efetivo de alertas de orçamento não foi comprovado e não será provocado por gasto deliberado. Componentes de dados permanecem pendentes.
