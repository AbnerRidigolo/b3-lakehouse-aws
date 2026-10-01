# Evidência: bootstrap implantado

- Região: us-east-1.
- Apply do plano aprovado: 12 recursos criados, zero alterados, zero destruídos.
- Bucket de estado privado, com versionamento, AES256 e política que exige TLS.
- GitHub OIDC e papéis plan/apply criados; execução de GitHub Actions ainda não testada.
- Estado do bootstrap migrado para S3, chave bootstrap/terraform.tfstate; lock nativo habilitado.
- Plano posterior à migração retornou sem diferenças.
- Metadados do objeto de estado confirmaram AES256 e versão S3; conteúdo do estado não foi publicado.
- Nenhum serviço de processamento, Organizations ou Identity Center criado.
- Custo real não apurado. Provisão inicial aprovada: USD 0,10 no primeiro mês sob as hipóteses de docs/costs/foundation.md; teto total do projeto USD 10.

Atualização: alertas de custo implantados e quatro commits publicados na branch fase-1-fundacao. Pendente na Fase 1: ativar a tag de alocação, configurar environments e variáveis no GitHub e validar CI/OIDC. Não declarar a fase completa antes disso.

O bootstrap agora exige backend.local.hcl ignorado no Git. Para clones novos, inicializar diretamente com a configuração do backend existente; não tentar recriar bucket ou provider. O estado permanece fora do Git.
