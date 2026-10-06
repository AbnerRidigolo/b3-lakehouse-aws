terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
}
variable "account_id" { type = string }
variable "region" { type = string }
variable "permissions_boundary_arn" { type = string }
variable "lambda_zip" { type = string }
variable "schedule_enabled" {
  type    = bool
  default = false
}
locals {
  name = "b3-lakehouse-aws-bronze"
}
resource "aws_s3_bucket" "bronze" {
  bucket        = "${local.name}-${var.account_id}"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "bronze" {
  bucket                  = aws_s3_bucket.bronze.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "bronze" {
  bucket = aws_s3_bucket.bronze.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "bronze" {
  bucket = aws_s3_bucket.bronze.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Deny", Principal = "*", Action = "s3:*"
    Resource  = [aws_s3_bucket.bronze.arn, "${aws_s3_bucket.bronze.arn}/*"]
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }] })
  depends_on = [aws_s3_bucket_public_access_block.bronze]
}
resource "aws_dynamodb_table" "runs" {
  name         = "${local.name}-runs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  attribute {
    name = "pk"
    type = "S"
  }
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}
resource "aws_cloudwatch_log_group" "bronze" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 3
}
resource "aws_iam_role" "lambda" {
  name                 = "${local.name}-lambda"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole"
  }] })
}
resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.id
  name = "bronze-only"
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = "${aws_s3_bucket.bronze.arn}/bronze/*" },
    { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.bronze.arn },
    { Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:UpdateItem"], Resource = aws_dynamodb_table.runs.arn },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.bronze.arn}:*" }
  ] })
}
resource "aws_lambda_function" "bronze" {
  function_name    = local.name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = var.lambda_zip
  source_code_hash = filebase64sha256(var.lambda_zip)
  timeout          = 180
  memory_size      = 512
  environment {
    variables = { BRONZE_BUCKET = aws_s3_bucket.bronze.id, RUNS_TABLE = aws_dynamodb_table.runs.name }
  }
  depends_on = [aws_iam_role_policy.lambda, aws_cloudwatch_log_group.bronze]
}
resource "aws_scheduler_schedule_group" "bronze" { name = local.name }
resource "aws_iam_role" "scheduler" {
  name                 = "${local.name}-scheduler"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "scheduler.amazonaws.com" }, Action = "sts:AssumeRole"
    Condition = { StringEquals = { "aws:SourceAccount" = var.account_id }, ArnEquals = { "aws:SourceArn" = aws_scheduler_schedule_group.bronze.arn } }
  }] })
}
resource "aws_iam_role_policy" "scheduler" {
  role = aws_iam_role.scheduler.id
  name = "invoke-bronze-only"
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "lambda:InvokeFunction", Resource = aws_lambda_function.bronze.arn
  }] })
}
resource "aws_scheduler_schedule" "bronze" {
  name                         = local.name
  group_name                   = aws_scheduler_schedule_group.bronze.name
  state                        = var.schedule_enabled ? "ENABLED" : "DISABLED"
  schedule_expression          = "cron(0 21 ? * MON-FRI *)"
  schedule_expression_timezone = "America/Sao_Paulo"
  flexible_time_window { mode = "OFF" }
  target {
    arn      = aws_lambda_function.bronze.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ scheduled_time = "<aws.scheduler.scheduled-time>" })
    retry_policy {
      maximum_retry_attempts       = 1
      maximum_event_age_in_seconds = 3600
    }
  }
  depends_on = [aws_iam_role_policy.scheduler]
}
output "bucket_name" { value = aws_s3_bucket.bronze.id }
output "function_name" { value = aws_lambda_function.bronze.function_name }
output "runs_table" { value = aws_dynamodb_table.runs.name }
