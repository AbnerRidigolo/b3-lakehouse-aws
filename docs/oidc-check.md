# Validação isolada de OIDC

O workflow `Verify AWS OIDC` é manual, executa somente na `main` e exige aprovação do environment correspondente. Selecionar `plan` ou `apply` testa um papel por execução. O proprietário deve revisar e aprovar cada execução no GitHub.

O teste obtém uma sessão temporária de 15 minutos e chama somente `sts:GetCallerIdentity`. Confere a conta e o ARN do papel assumido. Não executa Terraform, não lê o estado S3, não usa o secret de e-mail e não publica artifacts. Um teste bem-sucedido comprova a confiança OIDC, mas não comprova as permissões necessárias para plan/apply.

## Estado da configuração

- PR #1 mesclado na main; validação offline da correção de checksums passou.
- Environments aws-plan e aws-apply configurados com AbnerRidigolo como revisor obrigatório.
- aws-apply restrito à branch main.
- Oito variáveis cadastradas; DEPLOY_ENABLED permanece false.
- Secret BUDGET_ALERT_EMAIL cadastrado e existência verificada, sem publicar seu valor.
- Testes OIDC ainda não executados: este workflow precisa ser publicado, revisado e mesclado pelo proprietário.

## Antes de habilitar implantação

O workflow de infraestrutura atual transfere reviewed.tfplan por GitHub artifact. O plano pode conter dados privados do estado e valores sensíveis. Como o repositório é público, é necessário proteger essa transferência antes de habilitar DEPLOY_ENABLED. A aprovação dos environments não torna artifacts privados. Não executar esse workflow até corrigir a transferência do plano.
