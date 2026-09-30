# Fundação: estimativa e controle

Teto autorizado pelo proprietário: USD 10 para todo o projeto. Interpretação conservadora: consumo bruto antes de créditos. Reserva operacional: USD 2, não disponível para novos experimentos sem revisão.

## Bootstrap proposto

Região: us-east-1, conforme escopo original. O login em Ohio não altera esta decisão de implantação.

Plano autenticado gerado localmente: 12 recursos Terraform a criar, nenhum a modificar ou destruir. Inclui um bucket S3 com quatro configurações de segurança, um provider OIDC, dois papéis IAM e quatro políticas inline. Nenhum recurso aplicado.

## Estimativa preliminar, não custo medido

Para o estado, assumindo no máximo 0,1 GB incluindo versões durante 30 dias, 1.000 requisições de escrita/listagem e 10.000 leituras, reservar até USD 0,10 para o bootstrap e manutenção inicial do estado. É uma provisão conservadora para esse uso pequeno, não um limite imposto pela AWS. Revisar tarifas regionais e consumo antes do apply; custos acumulam enquanto o bucket e versões permanecerem.

O monitoramento e as notificações de Budgets não têm tarifa de uso segundo a página oficial. Não criamos relatórios pagos nem ações. O deploy dos budgets ocorrerá separadamente depois do bootstrap. IAM/OIDC não inicia capacidade de processamento.

Não inclui Glue, EMR, Athena, Fargate, CloudWatch ou backfill: cada execução terá previsão própria e aprovação. O histórico completo não está autorizado por essa estimativa. Não prometer projeto integral dentro de USD 10 antes de medir as etapas.

## Evidências

- Provider HashiCorp AWS 6.66.0 e Terraform 1.16.2.
- Formatação e validação de três diretórios Terraform concluídas.
- Quatro cenários de teste Terraform com providers simulados aprovados.
- Quatro testes Python aprovados, incluindo valores inválidos, reserva e uso ainda não faturado.
- CLI autenticada; Terraform reconheceu nativamente o login temporário, sem credential_process adicional.
- Ausência de provider GitHub OIDC existente confirmada por consulta somente de leitura.

## Antes de aprovar

Confirmar limite previsto de USD 0,10 para esta etapa, revisão do plano local e autorização para aplicar o bootstrap. O escopo original reserva esse apply local ao proprietário. Não fazer push, configurar environments ou ampliar papéis sem a autorização correspondente.

Fontes consultadas:
- https://aws.amazon.com/s3/pricing/
- https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/

Nenhum valor acima representa medição de faturamento.
