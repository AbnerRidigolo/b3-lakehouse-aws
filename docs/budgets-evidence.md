# Evidência: alertas de custo implantados

Dois budgets CUSTOM criados, com limite de USD 10 para o intervalo 30/09/2026 a 01/12/2026. O limite é total do projeto no intervalo, não reinicia mensalmente. Se houver extensão do projeto, revisar a data de encerramento sem reiniciar a data inicial ou desconsiderar consumo anterior.

- b3-lakehouse-aws-total: filtro Project=b3-lakehouse-aws; alertas ACTUAL acima de 50%, 75%, 90% e 100%.
- b3-lakehouse-aws-account-guard: toda a conta; alerta ACTUAL acima de 75%. Pode incluir custos alheios ao projeto.
- Créditos e reembolsos excluídos do cálculo para não ocultar consumo.
- Destinatário configurado com o e-mail fornecido, mantido somente em configuração local ignorada e no estado privado.
- Sem relatórios pagos, ações automáticas ou hard cap de faturamento.
- Apply: 2 criados, 0 alterados, 0 destruídos.
- Plano posterior: nenhuma diferença.

## Limitação atual

A consulta de tags de alocação retornou lista vazia para Project. Ainda não foi possível ativá-la; pode levar até 24 horas para aparecer. Até a ativação e disponibilização dos dados, o budget filtrado por projeto pode não refletir consumo. O guard da conta está configurado como cobertura adicional, mas ambos têm atraso de faturamento.

Recebimento efetivo de e-mail não foi comprovado: nenhum limite foi deliberadamente excedido. O custo real ainda não foi apurado; não interpretar ausência de alerta como gasto zero.

## GitHub

Repositório remoto inicialmente vazio. A publicação dos commits ainda depende da autorização do proprietário. Antes de habilitar DEPLOY_ENABLED, configurar e verificar os environments aws-plan e aws-apply, revisão obrigatória e restrição de apply à main. Não fazer primeiro push diretamente na main para contornar a revisão; publicar a branch autorizada, e o proprietário define o fluxo inicial de PR/merge conforme o estado do repositório.
