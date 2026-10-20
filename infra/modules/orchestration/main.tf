terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
}
variable "account_id" { type = string }
variable "region" { type = string }
variable "sfn_boundary_arn" { type = string }
variable "scheduler_boundary_arn" { type = string }
variable "alert_email" {
  type      = string
  sensitive = true
}
variable "bronze_function_name" { type = string }
variable "silver_job_name" { type = string }
variable "runs_table" { type = string }
variable "gold_cluster_arn" { type = string }
variable "gold_task_definition_arn" { type = string }
variable "gold_network_configuration" {
  type = object({ awsvpcConfiguration = object({ subnets = list(string), securityGroups = list(string), assignPublicIp = string }) })
}
variable "schedule_enabled" {
  type    = bool
  default = false
}
locals {
  name      = "b3-lakehouse-aws-pipeline"
  tags      = { Project = "b3-lakehouse-aws", ManagedBy = "Terraform" }
  workgroup = "b3-lakehouse-aws-gold"
}
resource "aws_iam_role" "sfn" {
  name                 = local.name
  permissions_boundary = var.sfn_boundary_arn
  tags                 = local.tags
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "states.amazonaws.com" }, Action = "sts:AssumeRole"
    Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
  }] })
}
resource "aws_iam_role_policy" "sfn" {
  role   = aws_iam_role.sfn.id
  name   = "pipeline-only"
  policy = templatefile("${path.module}/sfn-policy.json.tftpl", { account = var.account_id, region = var.region })
}
resource "aws_sfn_state_machine" "pipeline" {
  name     = local.name
  type     = "STANDARD"
  role_arn = aws_iam_role.sfn.arn
  tags     = local.tags
  definition = templatefile("${path.module}/pipeline.asl.json.tftpl", {
    table                    = var.runs_table
    bronze_function_arn      = "arn:aws:lambda:${var.region}:${var.account_id}:function:${var.bronze_function_name}"
    silver_job               = var.silver_job_name
    gold_cluster_arn         = var.gold_cluster_arn
    gold_task_definition_arn = var.gold_task_definition_arn
    subnets                  = var.gold_network_configuration.awsvpcConfiguration.subnets
    security_groups          = var.gold_network_configuration.awsvpcConfiguration.securityGroups
  })
  depends_on = [aws_iam_role_policy.sfn]
}

# Failure path: execution status events -> SNS e-mail; undeliverable events -> SQS DLQ.
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name}-dlq"
  message_retention_seconds = 345600
  sqs_managed_sse_enabled   = true
  tags                      = local.tags
}
resource "aws_sns_topic" "alerts" {
  # AWS-managed SNS key cannot be used by EventBridge; messages carry only IDs and status.
  name = "b3-lakehouse-aws-alerts"
  tags = local.tags
}
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
resource "aws_cloudwatch_event_rule" "failed" {
  name = "${local.name}-failed"
  tags = local.tags
  event_pattern = jsonencode({
    source        = ["aws.states"]
    "detail-type" = ["Step Functions Execution Status Change"]
    detail        = { status = ["FAILED", "TIMED_OUT", "ABORTED"], stateMachineArn = [aws_sfn_state_machine.pipeline.arn] }
  })
}
resource "aws_cloudwatch_event_target" "failed" {
  rule = aws_cloudwatch_event_rule.failed.name
  arn  = aws_sns_topic.alerts.arn
  input_transformer {
    input_paths    = { status = "$.detail.status", execution = "$.detail.name" }
    input_template = "\"b3-lakehouse-aws pipeline <status>: execution <execution>. See Step Functions history and the pipeline items in DynamoDB.\""
  }
  retry_policy {
    maximum_retry_attempts       = 2
    maximum_event_age_in_seconds = 3600
  }
  dead_letter_config { arn = aws_sqs_queue.dlq.arn }
}
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sns:Publish", Resource = aws_sns_topic.alerts.arn,
    Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.failed.arn } } },
    { Effect = "Allow", Principal = { Service = "cloudwatch.amazonaws.com" }, Action = "sns:Publish", Resource = aws_sns_topic.alerts.arn,
    Condition = { ArnLike = { "aws:SourceArn" = "arn:aws:cloudwatch:${var.region}:${var.account_id}:alarm:b3-lakehouse-aws-*" } } }
  ] })
}
resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sqs:SendMessage", Resource = aws_sqs_queue.dlq.arn
    Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.failed.arn } }
  }] })
}

# Alarms: undelivered alerts, bronze errors and, only when scheduled, missing daily success.
resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name          = "${local.name}-dlq-not-empty"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = local.tags
}
resource "aws_cloudwatch_metric_alarm" "bronze_errors" {
  alarm_name          = "${local.name}-bronze-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.bronze_function_name }
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = local.tags
}
resource "aws_cloudwatch_metric_alarm" "missing_success" {
  # Weekends produce no execution; three empty days means a missed weekday.
  count               = var.schedule_enabled ? 1 : 0
  alarm_name          = "${local.name}-missing-success"
  namespace           = "AWS/States"
  metric_name         = "ExecutionsSucceeded"
  dimensions          = { StateMachineArn = aws_sfn_state_machine.pipeline.arn }
  statistic           = "Sum"
  period              = 86400
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = local.tags
}
resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = local.name
  dashboard_body = jsonencode({ widgets = [
    { type = "metric", x = 0, y = 0, width = 12, height = 6, properties = {
      title   = "Pipeline executions", region = var.region, stat = "Sum", period = 86400, view = "timeSeries",
      metrics = [for m in ["ExecutionsStarted", "ExecutionsSucceeded", "ExecutionsFailed", "ExecutionsTimedOut"] : ["AWS/States", m, "StateMachineArn", aws_sfn_state_machine.pipeline.arn]]
    } },
    { type = "metric", x = 12, y = 0, width = 12, height = 6, properties = {
      title   = "Pipeline duration (ms)", region = var.region, stat = "Maximum", period = 86400, view = "timeSeries",
      metrics = [["AWS/States", "ExecutionTime", "StateMachineArn", aws_sfn_state_machine.pipeline.arn]]
    } },
    { type = "metric", x = 0, y = 6, width = 12, height = 6, properties = {
      title   = "Bronze Lambda", region = var.region, stat = "Sum", period = 86400, view = "timeSeries",
      metrics = [["AWS/Lambda", "Errors", "FunctionName", var.bronze_function_name], ["AWS/Lambda", "Invocations", "FunctionName", var.bronze_function_name]]
    } },
    { type = "metric", x = 12, y = 6, width = 12, height = 6, properties = {
      title   = "Athena gold bytes scanned / DLQ", region = var.region, period = 86400, view = "timeSeries",
      metrics = [["AWS/Athena", "ProcessedBytes", "WorkGroup", local.workgroup, { stat = "Sum" }], ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.dlq.name, { stat = "Maximum", yAxis = "right" }]]
    } }
  ] })
}

# Scheduler replaces the direct bronze schedule. DISABLED unless explicitly approved.
resource "aws_scheduler_schedule_group" "pipeline" {
  name = local.name
  tags = local.tags
}
resource "aws_iam_role" "scheduler" {
  name                 = "${local.name}-scheduler"
  permissions_boundary = var.scheduler_boundary_arn
  tags                 = local.tags
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "scheduler.amazonaws.com" }, Action = "sts:AssumeRole"
    Condition = { StringEquals = { "aws:SourceAccount" = var.account_id }, ArnEquals = { "aws:SourceArn" = aws_scheduler_schedule_group.pipeline.arn } }
  }] })
}
resource "aws_iam_role_policy" "scheduler" {
  role   = aws_iam_role.scheduler.id
  name   = "start-pipeline-only"
  policy = templatefile("${path.module}/scheduler-policy.json.tftpl", { account = var.account_id, region = var.region })
}
resource "aws_scheduler_schedule" "pipeline" {
  name                         = local.name
  group_name                   = aws_scheduler_schedule_group.pipeline.name
  state                        = var.schedule_enabled ? "ENABLED" : "DISABLED"
  schedule_expression          = "cron(0 21 ? * MON-FRI *)"
  schedule_expression_timezone = "America/Sao_Paulo"
  flexible_time_window { mode = "OFF" }
  target {
    arn      = aws_sfn_state_machine.pipeline.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ scheduled_time = "<aws.scheduler.scheduled-time>" })
    retry_policy {
      maximum_retry_attempts       = 0
      maximum_event_age_in_seconds = 3600
    }
    dead_letter_config { arn = aws_sqs_queue.dlq.arn }
  }
  depends_on = [aws_iam_role_policy.scheduler]
}
output "state_machine_arn" { value = aws_sfn_state_machine.pipeline.arn }
output "alerts_topic_arn" { value = aws_sns_topic.alerts.arn }
output "dlq_url" { value = aws_sqs_queue.dlq.id }
output "dashboard_name" { value = aws_cloudwatch_dashboard.pipeline.dashboard_name }
