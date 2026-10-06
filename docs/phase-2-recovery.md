# Recuperação da implantação bronze — 06/10/2026

A segunda tentativa do run 37481607236 aprovou um plano de 13 criações. O apply atingiu o timeout de 15 minutos enquanto o provider aguardava HeadBucket. A política CI omitia s3:ListBucket, necessária para essa operação; a simulação IAM confirmou implicitDeny no papel apply para o bucket bronze.

O bucket, grupo de logs, tabela DynamoDB, dois papéis de serviço e grupo Scheduler foram criados, mas não gravados no estado remoto antes da interrupção. Nenhum dado foi carregado; Lambda e agendamento não foram criados.

Após confirmar ausência de workflows ativos, foi removido somente o lock órfão dessa execução. Os seis recursos existentes foram importados no estado remoto, sem exclusão ou recriação. Plan de recuperação: sete criações, uma atualização apenas de tags do bucket, zero exclusões. Scheduler permanece DISABLED.

Correção proposta: adicionar ListBucket e leituras de ACL, website, versionamento, aceleração, request payment e lifecycle exigidas pelo resourceBucketRead do provider AWS 6.66.0. Permissões restritas ao ARN do bucket bronze, nos papéis CI plan/apply. Não permite leitura do conteúdo dos objetos. Plano bootstrap: zero criações, duas atualizações de políticas, zero exclusões. Testes Terraform simulados passaram.

Referências: https://docs.aws.amazon.com/AmazonS3/latest/API/API_HeadBucket.html e https://github.com/hashicorp/terraform-provider-aws/blob/v6.66.0/internal/service/s3/bucket.go .

A atualização IAM e publicação do commit corretivo ainda aguardam autorização. Após o proprietário mesclar, gerar um plano novo no GitHub; não reutilizar o plano anterior ao import. A implantação restante e os dois testes de carga continuam no escopo da reserva USD 0,20 já aprovada. Registrar consumo observado ao final.

## Complemento da leitura S3

O run 37506328687 falhou no plan com AccessDenied para GetBucketCORS; apply não executou. A auditoria completa do resourceBucketRead identificou também logging, replication e Object Lock. Foram adicionadas quatro consultas de metadados aos mesmos dois papéis e ARN do bucket, no escopo da correção autorizada. Apply bootstrap: 0 criados, 2 alterados, 0 destruídos. Simulação IAM confirmou as 16 consultas S3 necessárias como allowed para plan e apply. Não foi concedido GetObject no bucket bronze aos papéis CI. Publicação dessa atualização no código ainda depende de autorização por commit.
