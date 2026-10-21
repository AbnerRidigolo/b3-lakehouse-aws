variable "enable_gold_permissions" {
  type    = bool
  default = false
}
locals {
  gold_name      = "${local.project}-gold"
  gold_bucket    = "arn:aws:s3:::${local.gold_name}-${var.account_id}"
  gold_roles     = [for kind in ["task", "execution"] : "arn:aws:iam::${var.account_id}:role/${local.gold_name}-${kind}"]
  gold_ecr       = "arn:aws:ecr:${var.region}:${var.account_id}:repository/${local.gold_name}"
  gold_workgroup = "arn:aws:athena:${var.region}:${var.account_id}:workgroup/${local.gold_name}"
  gold_catalog   = ["arn:aws:glue:${var.region}:${var.account_id}:catalog", "arn:aws:glue:${var.region}:${var.account_id}:database/b3_lakehouse_gold"]
  gold_logs      = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/b3-lakehouse-aws/gold"
  gold_ecs       = ["arn:aws:ecs:${var.region}:${var.account_id}:cluster/${local.gold_name}", "arn:aws:ecs:${var.region}:${var.account_id}:task-definition/${local.gold_name}:*"]
  gold_network   = [for kind in ["vpc", "subnet", "internet-gateway", "route-table", "security-group"] : "arn:aws:ec2:${var.region}:${var.account_id}:${kind}/*"]
}
resource "aws_iam_policy" "gold_boundary" {
  for_each = var.enable_gold_permissions ? toset(["task", "execution"]) : toset([])
  name     = "${local.gold_name}-${each.key}-boundary"
  policy   = templatefile("${path.module}/../modules/gold/${each.key}-policy.json.tftpl", { account = var.account_id, region = var.region })
}
resource "aws_iam_policy" "gold_ci" {
  for_each = var.enable_gold_permissions ? aws_iam_role.github : {}
  name     = "${local.gold_name}-ci-${each.key}"
  policy = jsonencode({ Version = "2012-10-17", Statement = concat([
    { Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketAcl", "s3:GetBucketCORS", "s3:GetBucketLogging", "s3:GetReplicationConfiguration", "s3:GetBucketObjectLockConfiguration", "s3:GetBucketWebsite", "s3:GetBucketVersioning", "s3:GetAccelerateConfiguration", "s3:GetBucketRequestPayment", "s3:GetLifecycleConfiguration", "s3:GetBucketLocation", "s3:GetBucketTagging", "s3:GetBucketPolicy", "s3:GetBucketPublicAccessBlock", "s3:GetEncryptionConfiguration"], Resource = local.gold_bucket },
    { Effect = "Allow", Action = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole"], Resource = local.gold_roles },
    { Effect = "Allow", Action = ["ecr:DescribeRepositories", "ecr:GetLifecyclePolicy", "ecr:ListTagsForResource"], Resource = local.gold_ecr },
    { Effect = "Allow", Action = ["athena:GetWorkGroup", "athena:ListTagsForResource"], Resource = local.gold_workgroup },
    { Effect = "Allow", Action = ["glue:GetDatabase", "glue:GetTags"], Resource = local.gold_catalog },
    { Effect = "Allow", Action = "logs:DescribeLogGroups", Resource = "*" },
    { Effect = "Allow", Action = "logs:ListTagsForResource", Resource = local.gold_logs },
    { Effect = "Allow", Action = ["ecs:DescribeClusters", "ecs:ListTagsForResource"], Resource = local.gold_ecs },
    # DescribeTaskDefinition and DeregisterTaskDefinition support no resource-level permissions.
    { Effect = "Allow", Action = "ecs:DescribeTaskDefinition", Resource = "*" }
    ], [for statement in [
      { Effect = "Allow", Action = ["s3:CreateBucket", "s3:DeleteBucket", "s3:PutBucketTagging", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketPublicAccessBlock", "s3:PutEncryptionConfiguration", "s3:PutLifecycleConfiguration"], Resource = local.gold_bucket },
      { Effect = "Allow", Action = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"], Resource = local.gold_roles, Condition = { StringEquals = { "iam:PermissionsBoundary" = [for p in aws_iam_policy.gold_boundary : p.arn] } } },
      { Effect = "Allow", Action = ["iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy"], Resource = local.gold_roles },
      { Effect = "Allow", Action = "iam:PassRole", Resource = local.gold_roles, Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } } },
      { Effect = "Allow", Action = ["ecr:CreateRepository", "ecr:DeleteRepository", "ecr:PutLifecyclePolicy", "ecr:DeleteLifecyclePolicy", "ecr:PutImageTagMutability", "ecr:TagResource", "ecr:UntagResource", "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:DescribeImages"], Resource = local.gold_ecr },
      { Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" },
      { Effect = "Allow", Action = ["athena:CreateWorkGroup", "athena:UpdateWorkGroup", "athena:DeleteWorkGroup", "athena:TagResource", "athena:UntagResource"], Resource = local.gold_workgroup },
      { Effect = "Allow", Action = ["glue:CreateDatabase", "glue:UpdateDatabase", "glue:DeleteDatabase", "glue:TagResource", "glue:UntagResource"], Resource = local.gold_catalog },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource"], Resource = "${local.gold_logs}:*" },
      { Effect = "Allow", Action = ["ecs:CreateCluster", "ecs:DeleteCluster", "ecs:UpdateCluster", "ecs:UpdateClusterSettings", "ecs:TagResource", "ecs:UntagResource"], Resource = local.gold_ecs },
      { Effect = "Allow", Action = "ecs:DeregisterTaskDefinition", Resource = "*" },
      { Effect = "Allow", Action = "ecs:RegisterTaskDefinition", Resource = "*", Condition = { StringEquals = { "aws:RequestTag/Project" = local.project } } }
  ] : statement if each.key == "apply"]) })
}
resource "aws_iam_policy" "gold_network_ci" {
  for_each = var.enable_gold_permissions ? aws_iam_role.github : {}
  name     = "${local.gold_name}-network-ci-${each.key}"
  policy = jsonencode({ Version = "2012-10-17", Statement = concat([
    { Effect = "Allow", Action = ["ec2:DescribeVpcs", "ec2:DescribeVpcAttribute", "ec2:DescribeSubnets", "ec2:DescribeInternetGateways", "ec2:DescribeRouteTables", "ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules", "ec2:DescribeNetworkInterfaces", "ec2:DescribeTags"], Resource = "*" }
    ], [for statement in [
      { Effect = "Allow", Action = ["ec2:CreateVpc", "ec2:CreateSubnet", "ec2:CreateInternetGateway", "ec2:CreateRouteTable", "ec2:CreateSecurityGroup"], Resource = local.gold_network, Condition = { StringEquals = { "aws:RequestTag/Project" = local.project } } },
      # The parent VPC is also authorized on these calls and carries no request tags.
      { Effect = "Allow", Action = ["ec2:CreateSubnet", "ec2:CreateRouteTable", "ec2:CreateSecurityGroup"], Resource = "arn:aws:ec2:${var.region}:${var.account_id}:vpc/*", Condition = { StringEquals = { "aws:ResourceTag/Project" = local.project } } },
      { Effect = "Allow", Action = "ec2:CreateTags", Resource = local.gold_network, Condition = { StringEquals = { "ec2:CreateAction" = ["CreateVpc", "CreateSubnet", "CreateInternetGateway", "CreateRouteTable", "CreateSecurityGroup"], "aws:RequestTag/Project" = local.project } } },
      { Effect = "Allow", Action = ["ec2:DeleteVpc", "ec2:ModifyVpcAttribute", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:DeleteInternetGateway", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:ReplaceRouteTableAssociation", "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress", "ec2:DeleteSecurityGroup", "ec2:CreateTags", "ec2:DeleteTags"], Resource = local.gold_network, Condition = { StringEquals = { "aws:ResourceTag/Project" = local.project } } }
  ] : statement if each.key == "apply"]) })
}
resource "aws_iam_role_policy_attachment" "gold_ci" {
  for_each   = aws_iam_policy.gold_ci
  role       = aws_iam_role.github[each.key].name
  policy_arn = each.value.arn
}
resource "aws_iam_role_policy_attachment" "gold_network_ci" {
  for_each   = aws_iam_policy.gold_network_ci
  role       = aws_iam_role.github[each.key].name
  policy_arn = each.value.arn
}
variable "create_ecs_service_role" {
  type    = bool
  default = false
}
resource "aws_iam_service_linked_role" "ecs" {
  count            = var.enable_gold_permissions && var.create_ecs_service_role ? 1 : 0
  aws_service_name = "ecs.amazonaws.com"
  lifecycle { prevent_destroy = true }
}
