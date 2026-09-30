mock_provider "aws" {}
variables {
  account_id        = "123456789012"
  state_bucket_name = "b3-lakehouse-aws-test-state"
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
    condition     = jsondecode(aws_iam_role.github["apply"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:AbnerRidigolo/b3-lakehouse-aws:environment:aws-apply"
    error_message = "Apply must trust only the approved repository environment."
  }
  assert {
    condition     = length(jsondecode(aws_iam_role_policy.state["plan"].policy).Statement) == 3 && jsondecode(aws_iam_role_policy.state["plan"].policy).Statement[1].Action == ["s3:GetObject"]
    error_message = "Plan can read state and manage the lock, but cannot overwrite state."
  }
}
