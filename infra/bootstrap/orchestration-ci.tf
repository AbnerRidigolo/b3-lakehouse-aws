variable "enable_orchestration_permissions" {
  type    = bool
  default = false
}
locals {
  pipeline_name  = "${local.project}-pipeline"
  pipeline_roles = [for suffix in ["", "-scheduler"] : "arn:aws:iam::${var.account_id}:role/${local.pipeline_name}${suffix}"]
  pipeline_sfn   = ["arn:aws:states:${var.region}:${var.account_id}:stateMachine:${local.pipeline_name}", "arn:aws:states:${var.region}:${var.account_id}:stateMachine:${local.pipeline_name}:*"]
  pipeline_sqs   = "arn:aws:sqs:${var.region}:${var.account_id}:${local.pipeline_name}-dlq"
  pipeline_sns   = ["arn:aws:sns:${var.region}:${var.account_id}:${local.project}-alerts", "arn:aws:sns:${var.region}:${var.account_id}:${local.project}-alerts:*"]
  pipeline_rule  = "arn:aws:events:${var.region}:${var.account_id}:rule/${local.pipeline_name}-failed"
  pipeline_alarm = "arn:aws:cloudwatch:${var.region}:${var.account_id}:alarm:${local.pipeline_name}-*"
  pipeline_board = "arn:aws:cloudwatch::${var.account_id}:dashboard/${local.pipeline_name}"
  pipeline_scheduler = [
    "arn:aws:scheduler:${var.region}:${var.account_id}:schedule-group/${local.pipeline_name}",
    "arn:aws:scheduler:${var.region}:${var.account_id}:schedule/${local.pipeline_name}/${local.pipeline_name}"
  ]
}
resource "aws_iam_policy" "pipeline_boundary" {
  for_each = var.enable_orchestration_permissions ? toset(["sfn", "scheduler"]) : toset([])
  name     = "${local.pipeline_name}-${each.key}-boundary"
  policy   = templatefile("${path.module}/../modules/orchestration/${each.key}-policy.json.tftpl", { account = var.account_id, region = var.region })
}
resource "aws_iam_policy" "pipeline_ci" {
  for_each = var.enable_orchestration_permissions ? aws_iam_role.github : {}
  name     = "${local.pipeline_name}-ci-${each.key}"
  policy = jsonencode({ Version = "2012-10-17", Statement = concat([
    { Effect = "Allow", Action = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies"], Resource = local.pipeline_roles },
    { Effect = "Allow", Action = ["states:DescribeStateMachine", "states:ListStateMachineVersions", "states:ListTagsForResource"], Resource = local.pipeline_sfn },
    { Effect = "Allow", Action = ["sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:ListQueueTags"], Resource = local.pipeline_sqs },
    { Effect = "Allow", Action = ["sns:GetTopicAttributes", "sns:ListTagsForResource", "sns:ListSubscriptionsByTopic", "sns:GetSubscriptionAttributes"], Resource = local.pipeline_sns },
    { Effect = "Allow", Action = ["events:DescribeRule", "events:ListTargetsByRule", "events:ListTagsForResource"], Resource = local.pipeline_rule },
    { Effect = "Allow", Action = ["cloudwatch:DescribeAlarms", "cloudwatch:ListTagsForResource"], Resource = local.pipeline_alarm },
    { Effect = "Allow", Action = "cloudwatch:GetDashboard", Resource = local.pipeline_board },
    { Effect = "Allow", Action = ["scheduler:GetSchedule", "scheduler:GetScheduleGroup", "scheduler:ListTagsForResource"], Resource = local.pipeline_scheduler }
    ], [for statement in [
      { Effect = "Allow", Action = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"], Resource = local.pipeline_roles, Condition = { StringEquals = { "iam:PermissionsBoundary" = [for p in aws_iam_policy.pipeline_boundary : p.arn] } } },
      { Effect = "Allow", Action = ["iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy"], Resource = local.pipeline_roles },
      { Effect = "Allow", Action = "iam:PassRole", Resource = local.pipeline_roles, Condition = { StringEquals = { "iam:PassedToService" = ["states.amazonaws.com", "scheduler.amazonaws.com"] } } },
      { Effect = "Allow", Action = ["states:CreateStateMachine", "states:UpdateStateMachine", "states:DeleteStateMachine", "states:TagResource", "states:UntagResource"], Resource = local.pipeline_sfn },
      { Effect = "Allow", Action = ["sqs:CreateQueue", "sqs:DeleteQueue", "sqs:SetQueueAttributes", "sqs:TagQueue", "sqs:UntagQueue"], Resource = local.pipeline_sqs },
      { Effect = "Allow", Action = ["sns:CreateTopic", "sns:DeleteTopic", "sns:SetTopicAttributes", "sns:TagResource", "sns:UntagResource", "sns:Subscribe", "sns:Unsubscribe", "sns:SetSubscriptionAttributes"], Resource = local.pipeline_sns },
      { Effect = "Allow", Action = ["events:PutRule", "events:DeleteRule", "events:PutTargets", "events:RemoveTargets", "events:TagResource", "events:UntagResource"], Resource = local.pipeline_rule },
      { Effect = "Allow", Action = ["cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:TagResource", "cloudwatch:UntagResource"], Resource = local.pipeline_alarm },
      { Effect = "Allow", Action = ["cloudwatch:PutDashboard", "cloudwatch:DeleteDashboards"], Resource = local.pipeline_board },
      { Effect = "Allow", Action = ["scheduler:CreateSchedule", "scheduler:UpdateSchedule", "scheduler:DeleteSchedule", "scheduler:CreateScheduleGroup", "scheduler:DeleteScheduleGroup", "scheduler:TagResource", "scheduler:UntagResource"], Resource = local.pipeline_scheduler }
  ] : statement if each.key == "apply"]) })
}
resource "aws_iam_role_policy_attachment" "pipeline_ci" {
  for_each   = aws_iam_policy.pipeline_ci
  role       = aws_iam_role.github[each.key].name
  policy_arn = each.value.arn
}
