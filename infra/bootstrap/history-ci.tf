variable "enable_history_permissions" {
  type    = bool
  default = false
}
variable "existing_emr_service_role_arn" {
  type    = string
  default = null
}
resource "aws_iam_service_linked_role" "history" {
  count            = var.enable_history_permissions && var.existing_emr_service_role_arn == null ? 1 : 0
  aws_service_name = "ops.emr-serverless.amazonaws.com"
  lifecycle { prevent_destroy = true }
}
locals {
  history_role      = "arn:aws:iam::${var.account_id}:role/${local.project}-history-2025"
  history_glue_role = "arn:aws:iam::${var.account_id}:role/${local.project}-history-2025-glue"
  history_glue_job  = "arn:aws:glue:${var.region}:${var.account_id}:job/${local.project}-history-2025-glue"
  history_logs      = [for suffix in ["error", "output"] : "arn:aws:logs:${var.region}:${var.account_id}:log-group:/b3-lakehouse-aws/history-2025/${suffix}"]
  history_apps      = "arn:aws:emr-serverless:${var.region}:${var.account_id}:/applications/*"
  history_tags      = { StringEquals = { "aws:ResourceTag/Project" = local.project, "aws:ResourceTag/Component" = "history-2025" } }
}
resource "aws_iam_policy" "history_boundary" {
  count  = var.enable_history_permissions ? 1 : 0
  name   = "${local.project}-history-2025-boundary"
  policy = templatefile("${path.module}/../modules/history/runtime-policy.json.tftpl", { account_id = var.account_id, region = var.region })
}
resource "aws_iam_policy" "history_ci" {
  for_each = var.enable_history_permissions ? aws_iam_role.github : {}
  name     = "${local.project}-history-ci-${each.key}"
  policy = jsonencode({ Version = "2012-10-17", Statement = concat([
    { Effect = "Allow", Action = ["emr-serverless:GetApplication", "emr-serverless:ListTagsForResource"], Resource = local.history_apps, Condition = local.history_tags },
    { Effect = "Allow", Action = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies"], Resource = [local.history_role, local.history_glue_role] },
    { Effect = "Allow", Action = ["glue:GetJob", "glue:GetTags"], Resource = local.history_glue_job },
    { Effect = "Allow", Action = "logs:ListTagsForResource", Resource = local.history_logs }
    ], [for statement in [
      # CreateApplication has no resource-level ARN authorization. Bound the
      # wildcard to this regional, tagged pilot; existing applications stay scoped.
      { Effect = "Allow", Action = "emr-serverless:CreateApplication", Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = var.region, "aws:RequestTag/Project" = local.project, "aws:RequestTag/Component" = "history-2025" } } },
      { Effect = "Allow", Action = ["emr-serverless:UpdateApplication", "emr-serverless:DeleteApplication", "emr-serverless:TagResource", "emr-serverless:UntagResource"], Resource = local.history_apps, Condition = local.history_tags },
      { Effect = "Allow", Action = "emr-serverless:TagResource", Resource = local.history_apps, Condition = { StringEquals = { "aws:RequestTag/Project" = local.project, "aws:RequestTag/Component" = "history-2025" } } },
      { Effect = "Allow", Action = ["glue:CreateJob", "glue:UpdateJob", "glue:DeleteJob", "glue:TagResource", "glue:UntagResource"], Resource = local.history_glue_job },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource"], Resource = [for arn in local.history_logs : "${arn}:*"] },
      { Effect = "Allow", Action = "iam:PassRole", Resource = local.history_glue_role, Condition = { StringEquals = { "iam:PassedToService" = "glue.amazonaws.com" } } },
      { Effect = "Allow", Action = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"], Resource = [local.history_role, local.history_glue_role], Condition = { StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.history_boundary[0].arn } } },
      { Effect = "Allow", Action = ["iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy"], Resource = [local.history_role, local.history_glue_role] }
  ] : statement if each.key == "apply"]) })
  # Existing silver CI policy handles scripts/history-*; no data writes here.
  # No StartApplication or StartJobRun. PassRole only provisions the bounded Glue job.
}

resource "aws_iam_role_policy_attachment" "history_ci" {
  for_each   = aws_iam_policy.history_ci
  role       = aws_iam_role.github[each.key].name
  policy_arn = each.value.arn
}
