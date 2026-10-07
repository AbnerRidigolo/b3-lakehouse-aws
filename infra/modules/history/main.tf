terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
}
variable "account_id" { type = string }
variable "region" { type = string }
variable "permissions_boundary_arn" { type = string }
locals { name = "b3-lakehouse-aws-history-2025" }
resource "aws_emrserverless_application" "history" {
  name          = local.name
  release_label = "emr-7.10.0"
  type          = "spark"
  architecture  = "X86_64"
  tags          = { Project = "b3-lakehouse-aws", Component = "history-2025" }
  maximum_capacity {
    cpu    = "4 vCPU"
    memory = "16 GB"
    disk   = "40 GB"
  }
  auto_start_configuration { enabled = true }
  auto_stop_configuration {
    enabled              = true
    idle_timeout_minutes = 1
  }
  scheduler_configuration {
    max_concurrent_runs   = 1
    queue_timeout_minutes = 15
  }
  # No initial_capacity: creation never warms up billable workers.
}
resource "aws_iam_role" "history" {
  name                 = local.name
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Action = "sts:AssumeRole", Principal = { Service = "emr-serverless.amazonaws.com" }
    Condition = { StringEquals = { "aws:SourceAccount" = var.account_id }, ArnEquals = { "aws:SourceArn" = aws_emrserverless_application.history.arn } }
  }] })
}
resource "aws_iam_role_policy" "history" {
  role   = aws_iam_role.history.id
  name   = "historical-silver-only"
  policy = templatefile("${path.module}/runtime-policy.json.tftpl", { account_id = var.account_id, region = var.region })
}
resource "aws_s3_object" "artifacts" {
  for_each               = toset(["history-job.py", "history-libs.zip", "history-sdk.zip"])
  bucket                 = "b3-lakehouse-aws-silver-${var.account_id}"
  key                    = "scripts/${each.value}"
  source                 = "${path.module}/../../../artifacts/${each.value}"
  source_hash            = filesha256("${path.module}/../../../artifacts/${each.value}")
  server_side_encryption = "AES256"
}
output "application_id" { value = aws_emrserverless_application.history.id }
output "role_arn" { value = aws_iam_role.history.arn }
