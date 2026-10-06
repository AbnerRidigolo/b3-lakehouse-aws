mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/b3-lakehouse-aws-bronze-lambda" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-1:123456789012:function:b3-lakehouse-aws-bronze" }
  }
}
variables {
  account_id               = "123456789012"
  region                   = "us-east-1"
  lambda_zip               = "../../../artifacts/bronze.zip"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/b3-lakehouse-aws-bronze-boundary"
}
run "no_public_data_or_unapproved_schedule" {
  command = apply
  assert {
    condition     = aws_s3_bucket_public_access_block.bronze.block_public_policy && !aws_s3_bucket.bronze.force_destroy
    error_message = "Bronze must remain private and retain objects on destroy."
  }
  assert {
    condition     = aws_scheduler_schedule.bronze.state == "DISABLED" && aws_dynamodb_table.runs.billing_mode == "PAY_PER_REQUEST"
    error_message = "Scheduling requires separate approval; capacity is on demand."
  }
  assert {
    condition     = aws_lambda_function.bronze.timeout == 180 && aws_lambda_function.bronze.memory_size == 512 && length(aws_lambda_function.bronze.vpc_config) == 0
    error_message = "Keep bounded execution without VPC/NAT."
  }
  assert {
    condition     = aws_iam_role.lambda.permissions_boundary == var.permissions_boundary_arn && aws_iam_role.scheduler.permissions_boundary == var.permissions_boundary_arn
    error_message = "Both service roles require the reviewed boundary."
  }
}
