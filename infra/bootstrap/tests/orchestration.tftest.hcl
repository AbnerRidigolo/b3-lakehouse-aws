mock_provider "aws" {
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock-pipeline-boundary" }
  }
}
variables {
  account_id                       = "123456789012"
  state_bucket_name                = "b3-lakehouse-aws-test-state"
  existing_emr_service_role_arn    = "arn:aws:iam::123456789012:role/aws-service-role/ops.emr-serverless.amazonaws.com/AWSServiceRoleForAmazonEMRServerless"
  enable_orchestration_permissions = true
}
run "orchestration_ci_cannot_start_executions" {
  command = apply
  assert {
    condition     = alltrue([for p in concat(values(aws_iam_policy.pipeline_ci), values(aws_iam_policy.pipeline_boundary)) : length(p.policy) <= 6144])
    error_message = "Managed IAM policy exceeds 6144 characters."
  }
  assert {
    condition     = !strcontains(aws_iam_policy.pipeline_ci["apply"].policy, "StartExecution") && !strcontains(aws_iam_policy.pipeline_ci["apply"].policy, "RunTask") && !strcontains(aws_iam_policy.pipeline_ci["plan"].policy, "iam:PassRole") && !strcontains(aws_iam_policy.pipeline_ci["plan"].policy, "Create")
    error_message = "Deployment never runs the pipeline; plan stays read-only."
  }
  assert {
    condition     = !strcontains(aws_iam_policy.pipeline_boundary["sfn"].policy, "iam:Create") && !strcontains(aws_iam_policy.pipeline_boundary["scheduler"].policy, "lambda:") && strcontains(aws_iam_policy.pipeline_boundary["scheduler"].policy, "states:StartExecution")
    error_message = "Runtime boundaries stay scoped: the scheduler only starts the pipeline."
  }
  assert {
    condition = alltrue([for role in ["plan", "apply"] : anytrue([for s in jsondecode(aws_iam_policy.pipeline_ci[role].policy).Statement :
    s.Resource == "*" && contains(try(tolist(s.Action), [s.Action]), "states:ValidateStateMachineDefinition") && contains(try(tolist(s.Action), [s.Action]), "sns:GetSubscriptionAttributes")])])
    error_message = "Plan validates the definition and reads the subscription; both need Resource * (no resource-level support)."
  }
  assert {
    condition = anytrue([for s in jsondecode(aws_iam_policy.pipeline_ci["apply"].policy).Statement :
    s.Resource == "*" && contains(try(tolist(s.Action), [s.Action]), "sns:Unsubscribe") && contains(try(tolist(s.Action), [s.Action]), "sns:SetSubscriptionAttributes")])
    error_message = "Subscription updates and removal support no resource-level permissions."
  }
  assert {
    condition     = strcontains(aws_iam_policy.pipeline_ci["plan"].policy, "iam:ListInstanceProfilesForRole")
    error_message = "Role deletion lists instance profiles first; without it teardown fails."
  }
}
