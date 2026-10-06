variable "enable_bronze_permissions" {
  type    = bool
  default = false
}
locals {
  bronze_name   = "${local.project}-bronze"
  bronze_bucket = "arn:aws:s3:::${local.bronze_name}-${var.account_id}"
  bronze_table  = "arn:aws:dynamodb:${var.region}:${var.account_id}:table/${local.bronze_name}-runs"
  bronze_lambda = "arn:aws:lambda:${var.region}:${var.account_id}:function:${local.bronze_name}"
  bronze_logs   = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${local.bronze_name}"
  bronze_roles  = [for service in ["lambda", "scheduler"] : "arn:aws:iam::${var.account_id}:role/${local.bronze_name}-${service}"]
  bronze_scheduler = [
    "arn:aws:scheduler:${var.region}:${var.account_id}:schedule-group/${local.bronze_name}",
    "arn:aws:scheduler:${var.region}:${var.account_id}:schedule/${local.bronze_name}/${local.bronze_name}"
  ]
}
resource "aws_iam_policy" "bronze_boundary" {
  count = var.enable_bronze_permissions ? 1 : 0
  name  = "${local.bronze_name}-boundary"
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = "${local.bronze_bucket}/bronze/*" },
    { Effect = "Allow", Action = "s3:ListBucket", Resource = local.bronze_bucket },
    { Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:UpdateItem"], Resource = local.bronze_table },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${local.bronze_logs}:*" },
    { Effect = "Allow", Action = "lambda:InvokeFunction", Resource = local.bronze_lambda }
  ] })
}
resource "aws_iam_role_policy" "bronze_ci" {
  for_each = var.enable_bronze_permissions ? aws_iam_role.github : {}
  role     = each.value.id
  name     = "phase-2-bronze-only"
  policy = jsonencode({ Version = "2012-10-17", Statement = concat([
    { Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketAcl", "s3:GetBucketCORS", "s3:GetBucketLogging", "s3:GetReplicationConfiguration", "s3:GetBucketObjectLockConfiguration", "s3:GetBucketWebsite", "s3:GetBucketVersioning", "s3:GetAccelerateConfiguration", "s3:GetBucketRequestPayment", "s3:GetLifecycleConfiguration", "s3:GetBucketLocation", "s3:GetBucketTagging", "s3:GetBucketPolicy", "s3:GetBucketPublicAccessBlock", "s3:GetEncryptionConfiguration"], Resource = local.bronze_bucket },
    { Effect = "Allow", Action = ["dynamodb:DescribeTable", "dynamodb:DescribeTimeToLive", "dynamodb:DescribeContinuousBackups", "dynamodb:ListTagsOfResource"], Resource = local.bronze_table },
    { Effect = "Allow", Action = ["lambda:GetFunction", "lambda:GetFunctionConfiguration", "lambda:ListTags", "lambda:GetFunctionCodeSigningConfig", "lambda:GetFunctionConcurrency"], Resource = local.bronze_lambda },
    { Effect = "Allow", Action = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies"], Resource = local.bronze_roles },
    { Effect = "Allow", Action = ["scheduler:GetSchedule", "scheduler:GetScheduleGroup", "scheduler:ListTagsForResource"], Resource = local.bronze_scheduler },
    # This read API does not support individual log-group ARNs.
    { Effect = "Allow", Action = "logs:DescribeLogGroups", Resource = "*" },
    { Effect = "Allow", Action = "logs:ListTagsForResource", Resource = local.bronze_logs }
    ], [for statement in [
      { Effect = "Allow", Action = ["s3:CreateBucket", "s3:DeleteBucket", "s3:PutBucketTagging", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketPublicAccessBlock", "s3:PutEncryptionConfiguration"], Resource = local.bronze_bucket },
      { Effect = "Allow", Action = ["dynamodb:CreateTable", "dynamodb:UpdateTable", "dynamodb:DeleteTable", "dynamodb:UpdateTimeToLive", "dynamodb:TagResource", "dynamodb:UntagResource"], Resource = local.bronze_table },
      { Effect = "Allow", Action = ["lambda:CreateFunction", "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration", "lambda:DeleteFunction", "lambda:TagResource", "lambda:UntagResource"], Resource = local.bronze_lambda },
      { Effect = "Allow", Action = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"], Resource = local.bronze_roles, Condition = { StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.bronze_boundary[0].arn } } },
      { Effect = "Allow", Action = ["iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy"], Resource = local.bronze_roles },
      { Effect = "Allow", Action = "iam:PassRole", Resource = local.bronze_roles, Condition = { StringEquals = { "iam:PassedToService" = ["lambda.amazonaws.com", "scheduler.amazonaws.com"] } } },
      { Effect = "Allow", Action = ["scheduler:CreateSchedule", "scheduler:UpdateSchedule", "scheduler:DeleteSchedule", "scheduler:CreateScheduleGroup", "scheduler:DeleteScheduleGroup", "scheduler:TagResource", "scheduler:UntagResource"], Resource = local.bronze_scheduler },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource"], Resource = "${local.bronze_logs}:*" }
  ] : statement if each.key == "apply"]) })
}
