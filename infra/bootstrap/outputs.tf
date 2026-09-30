output "state_bucket" { value = aws_s3_bucket.state.id }
output "plan_role_arn" { value = aws_iam_role.github["plan"].arn }
output "apply_role_arn" { value = aws_iam_role.github["apply"].arn }
output "backend_configuration" {
  value = {
    bucket = aws_s3_bucket.state.id, key = local.state_key
    region = var.region, encrypt = true, use_lockfile = true
  }
}
