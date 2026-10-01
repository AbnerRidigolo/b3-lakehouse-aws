# ValidaÃ§Ã£o isolada de OIDC

O workflow `Verify AWS OIDC` Ã© manual, executa somente na `main` e exige aprovaÃ§Ã£o do environment correspondente. Selecionar `plan` ou `apply` testa um papel por execuÃ§Ã£o. O proprietÃ¡rio deve revisar e aprovar cada execuÃ§Ã£o no GitHub.

O teste obtÃ©m uma sessÃ£o temporÃ¡ria de 15 minutos e chama somente `sts:GetCallerIdentity`. Confere a conta e o ARN do papel assumido. NÃ£o executa Terraform, nÃ£o lÃª o estado S3, nÃ£o usa o secret de e-mail e nÃ£o publica artifacts. Um teste bem-sucedido comprova a confianÃ§a OIDC, mas nÃ£o comprova as permissÃµes necessÃ¡rias para plan/apply.

## Estado da configuraÃ§Ã£o

- PR #1 mesclado na main; validaÃ§Ã£o offline da correÃ§Ã£o de checksums passou.
- Environments aws-plan e aws-apply configurados com AbnerRidigolo como revisor obrigatÃ³rio.
- aws-apply restrito Ã  branch main.
- Oito variÃ¡veis cadastradas; DEPLOY_ENABLED permanece false.
- Secret BUDGET_ALERT_EMAIL cadastrado e existÃªncia verificada, sem publicar seu valor.
- Testes OIDC ainda nÃ£o executados: este workflow precisa ser publicado, revisado e mesclado pelo proprietÃ¡rio.

## Antes de habilitar implantaÃ§Ã£o

A correção local transfere somente reviewed.tfplan.enc por artifact, com retenção de um dia. Aead do PyNaCl fornece criptografia autenticada, com nonce aleatório e contexto de execução/commit. Apply autentica e recupera exatamente o plano produzido por plan. Chave errada, outro contexto ou adulteração interrompem a operação antes de gravar o plano decifrado.

Cadastrar TF_PLAN_ENCRYPTION_KEY como secret do repositório (32 bytes aleatórios em Base64). Não imprimir, versionar ou enviar essa chave em artifacts. A chave deve permanecer disponível durante as execuções pendentes; uma rotação requer regenerar planos. Aprovar aws-plan somente após revisar o código do PR, pois ele executa com acesso ao secret e à AWS.

Documentação: https://pynacl.readthedocs.io/en/latest/secret/ e https://docs.github.com/en/actions/reference/security/oidc .

Pendências: publicação e revisão da correção, criação do secret e validação integrada de plan/apply. DEPLOY_ENABLED permanece false. OIDC validado não comprova acesso ao backend nem execução Terraform. Tag de alocação e custo real também precisam ser verificados antes de encerrar a fase 1.

## Atualização em 01/10/2026

Correção publicada e mesclada no PR #3; secret de criptografia cadastrado. DEPLOY_ENABLED agora true, conforme autorização. Plan manual e publicação de artifact criptografado passaram; apply foi ignorado pela condição de execução manual plan. Consulte foundation-validation.md para a próxima validação e custo observado.
