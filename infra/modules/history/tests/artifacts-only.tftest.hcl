mock_provider "aws" {}
variables {
  account_id               = "123456789012"
  region                   = "us-east-1"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/b3-lakehouse-aws-history-2025-boundary"
  emr_enabled              = false
}
run "preserve_artifacts_without_attempting_emr" {
  command = apply
  assert {
    condition     = length(aws_s3_object.artifacts) == 3 && length(aws_emrserverless_application.history) == 0 && length(aws_iam_role.history) == 0
    error_message = "Preserve all three uploaded scripts while disabling EMR creation."
  }
}
