variable "account_id" { type = string }
variable "alert_email" {
  type      = string
  sensitive = true
  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "A valid alert email is required."
  }
}
variable "project_start" { type = string }
variable "project_end" { type = string }
variable "total_limit_usd" {
  type    = number
  default = 10
  validation {
    condition     = var.total_limit_usd > 0 && var.total_limit_usd <= 10
    error_message = "The authorized total cap is USD 10."
  }
}

resource "aws_budgets_budget" "project" {
  account_id        = var.account_id
  name              = "b3-lakehouse-aws-total"
  budget_type       = "COST"
  limit_amount      = tostring(var.total_limit_usd)
  limit_unit        = "USD"
  time_unit         = "CUSTOM"
  time_period_start = formatdate("YYYY-MM-DD_hh:mm", var.project_start)
  time_period_end   = formatdate("YYYY-MM-DD_hh:mm", var.project_end)
  cost_types {
    include_credit = false
    include_refund = false
    use_blended    = false
  }
  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$b3-lakehouse-aws"]
  }
  dynamic "notification" {
    for_each = [50, 75, 90, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
    }
  }
  tags = { Project = "b3-lakehouse-aws", ManagedBy = "Terraform" }
  lifecycle {
    precondition {
      condition     = can(timecmp(var.project_start, var.project_end)) ? timecmp(var.project_start, var.project_end) < 0 : false
      error_message = "Provide an explicit project interval in RFC3339 with end after start."
    }
  }
}

# Covers missing/unactivated project tags, but includes unrelated account usage.
resource "aws_budgets_budget" "account_guard" {
  account_id        = var.account_id
  name              = "b3-lakehouse-aws-account-guard"
  budget_type       = "COST"
  limit_amount      = tostring(var.total_limit_usd)
  limit_unit        = "USD"
  time_unit         = "CUSTOM"
  time_period_start = formatdate("YYYY-MM-DD_hh:mm", var.project_start)
  time_period_end   = formatdate("YYYY-MM-DD_hh:mm", var.project_end)
  cost_types {
    include_credit = false
    include_refund = false
    use_blended    = false
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 75
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
  tags = { Project = "b3-lakehouse-aws", ManagedBy = "Terraform" }
}
