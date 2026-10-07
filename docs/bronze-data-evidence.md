# Primeira carga bronze real — 06/10/2026

Data de referência: 01/10/2026. Carga executada manualmente na Lambda b3-lakehouse-aws-bronze em us-east-1, dentro da reserva USD 0,20 autorizada. Função respondeu SUCCESS; DynamoDB confirmou o status com leitura consistente.

- B3: ZIP original de 464.064 bytes; 15.700 cotações, 317 no escopo lote padrão/mercado à vista; rodapé no modo quotes_only.
- CDI (SGS 12): JSON original de 42 bytes, uma observação.
- Selic (SGS 11): JSON original de 42 bytes, uma observação.
- Dólar venda (SGS 1): JSON original de 40 bytes, uma observação.

Quatro objetos em bronze/source=.../reference_date=2026-10-01/, no bucket privado b3-lakehouse-aws-bronze-259081046223. Todos confirmaram AES256. Payloads foram recuperados para a pasta local ignorada, revalidados e seus hashes SHA-256 comparados com a resposta da Lambda e os metadados S3. Arquivos de dados não foram versionados.

Segunda invocação: ALREADY_SUCCESS. Listagens antes/depois confirmaram os mesmos quatro objetos, tamanhos, ETags e datas de modificação. Não houve nova coleta nem duplicação. Logs REPORT: primeira chamada faturou 4.692 ms e a segunda 114 ms, ambas com 512 MB (2,403 GB-s totais). Consumo de memória máximo observado: 113 MB.

Budget da conta consultado após os testes: USD 0,335, atualizado em 06/10/2026 às 20:19:32 de São Paulo. Esse valor pode incluir outros projetos e ainda não refletir essas invocações ou custos recentes; não é medição final por serviço. Créditos não entram no cálculo do budget.

## Recuperação Terraform

O apply da segunda tentativa do run 37520292341 criou a Lambda, mas falhou no refresh por ausência de lambda:ListVersionsByFunction. Código oficial do provider auditado; adicionada apenas essa leitura de metadados no ARN da Lambda bronze aos papéis CI, sem ampliar escrita. Apply bootstrap: 0 criados, 2 alterados, 0 destruídos.

Lambda verificada Active, Python 3.12, 512 MB, 180 s, papel correto e sem VPC. ZIP publicado foi lido e handler.py comparado com o Git revisado, normalizando finais de linha. Código confirmado igual. A marca tainted decorrente da falha de leitura foi removida para preservar a função.

O pacote local Windows diferia do runner Linux por finais de linha e metadados ZIP. Build corrigido com LF, create_system=3, timestamp e permissões fixos e ZIP_STORED (evita diferenças de compressor). Teste confirma bytes iguais entre fontes LF e CRLF.

Plano local de recuperação: duas criações (política de invocação do Scheduler e schedule DISABLED), uma atualização in-place do pacote da Lambda, zero exclusões. Correções publicadas no PR #8 e implantadas com sucesso no run 37549869974. Não habilitar agendamento diário automaticamente.


## Conclusão da infraestrutura bronze

Em 06/10/2026, o workflow https://github.com/AbnerRidigolo/b3-lakehouse-aws/actions/runs/37549869974 concluiu plan e apply com sucesso após o merge do PR #8. Verificações posteriores por AWS CLI confirmaram:

- Lambda Active, LastUpdateStatus Successful e CodeSha256 igual ao pacote portátil local.
- Scheduler DISABLED, cron de segunda a sexta às 21h, fuso America/Sao_Paulo, alvo Lambda bronze.
- Política invoke-bronze-only permite apenas lambda:InvokeFunction no ARN exato dessa função.
- Os quatro objetos bronze permanecem no S3; execução bronze#2026-10-01 permanece SUCCESS no DynamoDB, conferida com leitura consistente.
- Todos os 13 recursos do módulo bronze constam no estado remoto Terraform, além dos dois budgets.
- Budget da conta permanece em USD 0,335, atualização 06/10/2026 20:19:32 de São Paulo; budget filtrado pelo projeto informa USD 0,00, mas ambos têm atraso. Não interpretar o valor filtrado como custo real zero nem custo final.

Fase 2 tecnicamente validada. Agendamento permanece desativado. Silver, gold e orquestração ponta a ponta ainda não implementados.
