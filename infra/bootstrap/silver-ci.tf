variable "enable_silver_permissions" {
  type    = bool
  default = false
}
locals {
  silver_name   = "${local.project}-silver"
  silver_bucket = "arn:aws:s3:::${local.silver_name}-${var.account_id}"
  silver_role   = "arn:aws:iam::${var.account_id}:role/${local.silver_name}"
  silver_job    = "arn:aws:glue:${var.region}:${var.account_id}:job/${local.silver_name}"
  silver_catalog = [
    "arn:aws:glue:${var.region}:${var.account_id}:catalog",
    "arn:aws:glue:${var.region}:${var.account_id}:database/b3_lakehouse_silver",
    "arn:aws:glue:${var.region}:${var.account_id}:table/b3_lakehouse_silver/b3_daily",
    "arn:aws:glue:${var.region}:${var.account_id}:table/b3_lakehouse_silver/bcb_daily"
  ]
  silver_log_groups = [for suffix in ["error", "output"] : "arn:aws:logs:${var.region}:${var.account_id}:log-group:/b3-lakehouse-aws/silver/${suffix}"]
  silver_runtime = [
    { Effect = "Allow", Action = "s3:GetObject", Resource = ["${local.bronze_bucket}/bronze/*", "${local.silver_bucket}/scripts/*"] },
    { Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation"], Resource = [local.bronze_bucket, local.silver_bucket] },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"], Resource = ["${local.silver_bucket}/silver/*", "${local.silver_bucket}/temp/*"] },
    { Effect = "Allow", Action = ["glue:GetDatabase", "glue:GetTable", "glue:CreateTable", "glue:UpdateTable"], Resource = local.silver_catalog },
    { Effect = "Allow", Action = "glue:GetJobBookmark", Resource = local.silver_job },
    { Effect = "Allow", Action = "dynamodb:GetItem", Resource = local.bronze_table, Condition = { "ForAllValues:StringLike" = { "dynamodb:LeadingKeys" = ["bronze#*", "silver#*"] } } },
    { Effect = "Allow", Action = "dynamodb:UpdateItem", Resource = local.bronze_table, Condition = { "ForAllValues:StringLike" = { "dynamodb:LeadingKeys" = ["silver#*"] } } },
    { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = [for arn in local.silver_log_groups : "${arn}:*"] }
  ]
}
resource "aws_iam_policy" "silver_boundary" {
  count  = var.enable_silver_permissions ? 1 : 0
  name   = "${local.silver_name}-boundary"
  policy = jsonencode({ Version = "2012-10-17", Statement = local.silver_runtime })
}
resource "aws_iam_role_policy" "silver_ci" {
  for_each = var.enable_silver_permissions ? aws_iam_role.github : {}
  role     = each.value.id
  name     = "phase-3-silver-only"
  policy = jsonencode({ Version = "2012-10-17", Statement = concat([
    { Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketAcl", "s3:GetBucketCORS", "s3:GetBucketLogging", "s3:GetReplicationConfiguration", "s3:GetBucketObjectLockConfiguration", "s3:GetBucketWebsite", "s3:GetBucketVersioning", "s3:GetAccelerateConfiguration", "s3:GetBucketRequestPayment", "s3:GetLifecycleConfiguration", "s3:GetBucketLocation", "s3:GetBucketTagging", "s3:GetBucketPolicy", "s3:GetBucketPublicAccessBlock", "s3:GetEncryptionConfiguration"], Resource = local.silver_bucket },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectTagging"], Resource = "${local.silver_bucket}/scripts/*" },
    { Effect = "Allow", Action = ["glue:GetJob", "glue:GetTags"], Resource = local.silver_job },
    { Effect = "Allow", Action = ["glue:GetDatabase", "glue:GetTags"], Resource = local.silver_catalog },
    { Effect = "Allow", Action = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies"], Resource = local.silver_role },
    { Effect = "Allow", Action = "logs:DescribeLogGroups", Resource = "*" },
    { Effect = "Allow", Action = "logs:ListTagsForResource", Resource = local.silver_log_groups }
    ], [for statement in [
      { Effect = "Allow", Action = ["s3:CreateBucket", "s3:DeleteBucket", "s3:PutBucketTagging", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketPublicAccessBlock", "s3:PutEncryptionConfiguration", "s3:PutLifecycleConfiguration"], Resource = local.silver_bucket },
      { Effect = "Allow", Action = ["s3:PutObject", "s3:PutObjectTagging", "s3:DeleteObjectTagging", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"], Resource = "${local.silver_bucket}/scripts/*" },
      { Effect = "Allow", Action = ["glue:CreateJob", "glue:UpdateJob", "glue:DeleteJob", "glue:TagResource", "glue:UntagResource"], Resource = local.silver_job },
      { Effect = "Allow", Action = ["glue:CreateDatabase", "glue:UpdateDatabase", "glue:DeleteDatabase", "glue:TagResource", "glue:UntagResource"], Resource = local.silver_catalog },
      { Effect = "Allow", Action = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"], Resource = local.silver_role, Condition = { StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.silver_boundary[0].arn } } },
      { Effect = "Allow", Action = ["iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy"], Resource = local.silver_role },
      { Effect = "Allow", Action = "iam:PassRole", Resource = local.silver_role, Condition = { StringEquals = { "iam:PassedToService" = "glue.amazonaws.com" } } },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource"], Resource = [for arn in local.silver_log_groups : "${arn}:*"] }
  ] : statement if each.key == "apply"]) })
}
