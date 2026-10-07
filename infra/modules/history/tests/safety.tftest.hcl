mock_provider "aws" {
  mock_resource "aws_emrserverless_application" {
    defaults = { arn = "arn:aws:emr-serverless:us-east-1:123456789012:/applications/test" }
  }
}
variables {
  account_id               = "123456789012"
  region                   = "us-east-1"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/b3-lakehouse-aws-history-2025-boundary"
}
run "no_warm_capacity_or_unbounded_history" {
  command = apply
  assert {
    condition     = try(length(aws_emrserverless_application.history.initial_capacity), 0) == 0 && aws_emrserverless_application.history.maximum_capacity[0].cpu == "4 vCPU" && aws_emrserverless_application.history.maximum_capacity[0].memory == "16 GB"
    error_message = "No pre-initialized billed workers; cap total capacity."
  }
  assert {
    condition     = aws_emrserverless_application.history.auto_stop_configuration[0].idle_timeout_minutes == 1 && aws_emrserverless_application.history.scheduler_configuration[0].max_concurrent_runs == 1 && try(length(aws_emrserverless_application.history.network_configuration), 0) == 0
    error_message = "Auto-stop, one job and no VPC/NAT required."
  }
  assert {
    condition     = aws_iam_role.history.permissions_boundary == var.permissions_boundary_arn && !strcontains(aws_iam_role_policy.history.policy, "StartJobRun") && strcontains(aws_iam_role_policy.history.policy, "bronze/history/year=2025/")
    error_message = "Runtime remains restricted to the 2025 pilot."
  }
}
