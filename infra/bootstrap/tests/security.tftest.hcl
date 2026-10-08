mock_provider "aws" {
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock-reviewed-policy" }
  }
}
variables {
  account_id                    = "123456789012"
  state_bucket_name             = "b3-lakehouse-aws-test-state"
  existing_emr_service_role_arn = "arn:aws:iam::123456789012:role/aws-service-role/ops.emr-serverless.amazonaws.com/AWSServiceRoleForAmazonEMRServerless"
}
run "history_cannot_start_paid_compute" {
  command = apply
  variables { enable_history_permissions = true }
  assert {
    condition     = one([for s in jsondecode(aws_iam_policy.history_ci["apply"].policy).Statement : s if s.Action == "emr-serverless:CreateApplication"]).Resource == "*" && one([for s in jsondecode(aws_iam_policy.history_ci["apply"].policy).Statement : s if s.Action == "emr-serverless:CreateApplication"]).Condition.StringEquals["aws:RequestedRegion"] == var.region && one([for s in jsondecode(aws_iam_policy.history_ci["apply"].policy).Statement : s if s.Action == "emr-serverless:CreateApplication"]).Condition.StringEquals["aws:RequestTag/Component"] == "history-2025"
    error_message = "CreateApplication requires resource wildcard, bounded by region and pilot tags."
  }
  assert {
    condition     = !strcontains(aws_iam_policy.history_ci["apply"].policy, "StartJobRun") && !strcontains(aws_iam_policy.history_ci["apply"].policy, "StartApplication") && !strcontains(aws_iam_policy.history_ci["plan"].policy, "CreateApplication")
    error_message = "CI must not start paid workers or let plan create applications."
  }
  assert {
    condition     = strcontains(aws_iam_policy.history_boundary[0].policy, "bronze/history/year=2025/*") && !strcontains(aws_iam_policy.history_boundary[0].policy, "iam:") && !strcontains(aws_iam_policy.history_boundary[0].policy, "CreateTable")
    error_message = "Pilot runtime must not alter IAM, unrelated bronze years or create catalogs."
  }
}
run "silver_runtime_and_ci_boundaries" {
  command = apply
  variables { enable_silver_permissions = true }
  assert {
    condition     = !strcontains(aws_iam_policy.silver_boundary[0].policy, "iam:") && !strcontains(aws_iam_policy.silver_boundary[0].policy, "glue:StartJobRun")
    error_message = "Glue runtime cannot administer IAM or start additional billed jobs."
  }
  assert {
    condition     = !strcontains(aws_iam_role_policy.silver_ci["plan"].policy, "iam:PassRole") && !strcontains(aws_iam_role_policy.silver_ci["plan"].policy, "glue:CreateJob") && !strcontains(aws_iam_role_policy.silver_ci["apply"].policy, "glue:StartJobRun")
    error_message = "Plan remains read-only; deployment must never start billed Spark work."
  }
  assert {
    condition     = !strcontains(aws_iam_role_policy.silver_ci["apply"].policy, "/silver/*") && !strcontains(aws_iam_role_policy.silver_ci["apply"].policy, "iam:CreatePolicy")
    error_message = "CI cannot modify silver data or create an unbounded runtime policy."
  }
}
run "bronze_permissions_are_bounded" {
  command = apply
  variables { enable_bronze_permissions = true }
  assert {
    condition     = !strcontains(aws_iam_policy.bronze_boundary[0].policy, "iam:") && !strcontains(aws_iam_policy.bronze_boundary[0].policy, "s3:DeleteObject")
    error_message = "Runtime boundary must not administer IAM or delete bronze objects."
  }
  assert {
    condition     = !strcontains(aws_iam_role_policy.bronze_ci["plan"].policy, "iam:PassRole") && !strcontains(aws_iam_role_policy.bronze_ci["plan"].policy, "lambda:CreateFunction")
    error_message = "Plan must remain read-only for phase 2 resources."
  }
}
run "state_and_trust_boundaries" {
  command = apply
  assert {
    condition     = aws_s3_bucket_public_access_block.state.block_public_policy && aws_s3_bucket_public_access_block.state.restrict_public_buckets
    error_message = "State must not be public."
  }
  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled" && !aws_s3_bucket.state.force_destroy
    error_message = "Keep state recovery and prevent automatic object deletion."
  }
  assert {
    condition     = jsondecode(aws_iam_role.github["apply"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:AbnerRidigolo@135280329/b3-lakehouse-aws@1387924432:environment:aws-apply"
    error_message = "Apply must trust only the approved repository environment."
  }
  assert {
    condition     = length(jsondecode(aws_iam_role_policy.state["plan"].policy).Statement) == 3 && jsondecode(aws_iam_role_policy.state["plan"].policy).Statement[1].Action == ["s3:GetObject"]
    error_message = "Plan can read state and manage the lock, but cannot overwrite state."
  }
}
