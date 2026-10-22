mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/pipeline-test" }
  }
  mock_resource "aws_sfn_state_machine" {
    defaults = { arn = "arn:aws:states:us-east-1:123456789012:stateMachine:b3-lakehouse-aws-pipeline" }
  }
  mock_resource "aws_sqs_queue" {
    defaults = { arn = "arn:aws:sqs:us-east-1:123456789012:b3-lakehouse-aws-pipeline-dlq" }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-1:123456789012:b3-lakehouse-aws-alerts" }
  }
  mock_resource "aws_cloudwatch_event_rule" {
    defaults = { arn = "arn:aws:events:us-east-1:123456789012:rule/b3-lakehouse-aws-pipeline-failed" }
  }
  mock_resource "aws_scheduler_schedule_group" {
    defaults = { arn = "arn:aws:scheduler:us-east-1:123456789012:schedule-group/b3-lakehouse-aws-pipeline" }
  }
}
variables {
  account_id               = "123456789012"
  region                   = "us-east-1"
  sfn_boundary_arn         = "arn:aws:iam::123456789012:policy/b3-lakehouse-aws-pipeline-sfn-boundary"
  scheduler_boundary_arn   = "arn:aws:iam::123456789012:policy/b3-lakehouse-aws-pipeline-scheduler-boundary"
  alert_email              = "owner@example.com"
  bronze_function_name     = "b3-lakehouse-aws-bronze"
  silver_job_name          = "b3-lakehouse-aws-silver"
  runs_table               = "b3-lakehouse-aws-bronze-runs"
  gold_cluster_arn         = "arn:aws:ecs:us-east-1:123456789012:cluster/b3-lakehouse-aws-gold"
  gold_task_definition_arn = "arn:aws:ecs:us-east-1:123456789012:task-definition/b3-lakehouse-aws-gold:1"
  gold_network_configuration = { awsvpcConfiguration = {
    subnets = ["subnet-0123"], securityGroups = ["sg-0123"], assignPublicIp = "ENABLED"
  } }
}
run "disabled_schedule_and_bounded_definition" {
  command = apply
  assert {
    condition     = aws_scheduler_schedule.pipeline.state == "DISABLED" && length(aws_cloudwatch_metric_alarm.missing_success) == 0
    error_message = "Recurring runs stay disabled unless explicitly approved."
  }
  assert {
    condition     = one(aws_scheduler_schedule.pipeline.target).retry_policy[0].maximum_retry_attempts == 0
    error_message = "The scheduler must not start duplicate executions."
  }
  assert {
    condition     = jsondecode(aws_sfn_state_machine.pipeline.definition).TimeoutSeconds == 3600 && jsondecode(aws_sfn_state_machine.pipeline.definition).States.Gold.Arguments.NetworkConfiguration.AwsvpcConfiguration.Subnets == ["subnet-0123"]
    error_message = "Global timeout and the exported gold network must be rendered."
  }
  assert {
    condition     = aws_iam_role.sfn.permissions_boundary == var.sfn_boundary_arn && aws_iam_role.scheduler.permissions_boundary == var.scheduler_boundary_arn
    error_message = "Every role needs its reviewed permissions boundary."
  }
  assert {
    condition     = !strcontains(aws_iam_role_policy.sfn.policy, "\"*\"") && !strcontains(aws_iam_role_policy.sfn.policy, "iam:Create") && strcontains(aws_iam_role_policy.sfn.policy, "ecs-tasks.amazonaws.com")
    error_message = "No wildcard resources; PassRole only to ECS tasks."
  }
  assert {
    condition     = aws_sqs_queue.dlq.sqs_managed_sse_enabled && aws_sqs_queue.dlq.message_retention_seconds <= 345600
    error_message = "Encrypted DLQ with short retention."
  }
  assert {
    condition     = length(distinct([for s in jsondecode(aws_sns_topic_policy.alerts.policy).Statement : try(s.Sid, "")])) == length(jsondecode(aws_sns_topic_policy.alerts.policy).Statement) && alltrue([for s in jsondecode(aws_sns_topic_policy.alerts.policy).Statement : try(s.Sid, "") != ""])
    error_message = "SNS rejects topic policies without a unique Sid per statement."
  }
}
run "approved_schedule_adds_missing_run_alarm" {
  command = apply
  variables { schedule_enabled = true }
  assert {
    condition     = aws_scheduler_schedule.pipeline.state == "ENABLED" && length(aws_cloudwatch_metric_alarm.missing_success) == 1
    error_message = "An enabled schedule must be monitored for missing runs."
  }
}
