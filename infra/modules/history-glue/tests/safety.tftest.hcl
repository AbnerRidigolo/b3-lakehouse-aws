mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/b3-lakehouse-aws-history-2025-glue" }
  }
}
variables {
  account_id               = "123456789012"
  region                   = "us-east-1"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/b3-lakehouse-aws-history-2025-boundary"
}
run "one_bounded_glue_history_job" {
  command = apply
  assert {
    condition     = aws_glue_job.history.number_of_workers == 2 && aws_glue_job.history.timeout == 15 && aws_glue_job.history.max_retries == 0 && aws_glue_job.history.execution_property[0].max_concurrent_runs == 1
    error_message = "Keep one bounded run without retries or automatic execution."
  }
  assert {
    condition     = aws_glue_job.history.non_overridable_arguments["--year"] == "2025" && aws_glue_job.history.non_overridable_arguments["--engine"] == "glue" && aws_iam_role.glue.permissions_boundary == var.permissions_boundary_arn
    error_message = "Pin the authorized year, Glue engine and runtime boundary."
  }
  assert {
    condition     = aws_glue_job.history.connections == null && aws_cloudwatch_log_group.history["error"].retention_in_days == 3
    error_message = "No VPC/NAT and only short log retention."
  }
}
