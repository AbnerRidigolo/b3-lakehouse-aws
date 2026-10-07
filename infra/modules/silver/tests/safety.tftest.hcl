mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/b3-lakehouse-aws-silver" }
  }
}
variables {
  account_id               = "123456789012"
  region                   = "us-east-1"
  bronze_bucket            = "b3-lakehouse-aws-bronze-123456789012"
  runs_table               = "b3-lakehouse-aws-bronze-runs"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/b3-lakehouse-aws-silver-boundary"
}
run "bounded_spark_without_automatic_execution" {
  command = apply
  assert {
    condition     = aws_glue_job.silver.number_of_workers == 2 && aws_glue_job.silver.timeout == 10 && aws_glue_job.silver.max_retries == 0 && aws_glue_job.silver.execution_property[0].max_concurrent_runs == 1
    error_message = "Keep a bounded job, without automatic retries or concurrent runs."
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.data.block_public_policy && !aws_s3_bucket.data.force_destroy && aws_glue_job.silver.connections == null
    error_message = "No public data, destructive bucket cleanup or VPC/NAT connection."
  }
  assert {
    condition     = aws_iam_role.glue.permissions_boundary == var.permissions_boundary_arn && aws_glue_job.silver.non_overridable_arguments["--datalake-formats"] == "iceberg"
    error_message = "Keep the reviewed permissions boundary and Iceberg framework."
  }
}
