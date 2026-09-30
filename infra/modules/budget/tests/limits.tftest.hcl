mock_provider "aws" {}
variables {
  account_id    = "123456789012"
  alert_email   = "test@example.com"
  project_start = "2026-09-30T00:00:00Z"
  project_end   = "2026-12-01T00:00:00Z"
}
run "gross_total_no_monthly_reset" {
  command = plan
  assert {
    condition     = aws_budgets_budget.project.time_unit == "CUSTOM" && aws_budgets_budget.project.limit_amount == "10"
    error_message = "Budget must cover the complete project, not reset monthly."
  }
  assert {
    condition     = !aws_budgets_budget.project.cost_types[0].include_credit
    error_message = "Credits must not hide project consumption."
  }
}
run "reject_over_cap" {
  command = plan
  variables { total_limit_usd = 11 }
  expect_failures = [var.total_limit_usd]
}
run "reject_reversed_interval" {
  command = plan
  variables { project_end = "2026-09-01T00:00:00Z" }
  expect_failures = [aws_budgets_budget.project]
}
