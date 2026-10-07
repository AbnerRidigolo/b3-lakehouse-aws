terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
}
variable "account_id" { type = string }
variable "region" { type = string }
variable "permissions_boundary_arn" { type = string }
locals {
  name   = "b3-lakehouse-aws-history-2025-glue"
  bucket = "b3-lakehouse-aws-silver-${var.account_id}"
}
resource "aws_cloudwatch_log_group" "history" {
  for_each          = toset(["error", "output"])
  name              = "/b3-lakehouse-aws/history-2025/${each.key}"
  retention_in_days = 3
}
resource "aws_iam_role" "glue" {
  name                 = local.name
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "glue.amazonaws.com" }
  }] })
}
resource "aws_iam_role_policy" "glue" {
  role   = aws_iam_role.glue.id
  name   = "historical-silver-only"
  policy = templatefile("${path.module}/../history/runtime-policy.json.tftpl", { account_id = var.account_id, region = var.region })
}
resource "aws_glue_job" "history" {
  name              = local.name
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15
  max_retries       = 0
  execution_class   = "STANDARD"
  execution_property { max_concurrent_runs = 1 }
  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${local.bucket}/scripts/history-job.py"
  }
  non_overridable_arguments = {
    "--engine"                       = "glue"
    "--year"                         = "2025"
    "--bronze_bucket"                = "b3-lakehouse-aws-bronze-${var.account_id}"
    "--silver_bucket"                = local.bucket
    "--runs_table"                   = "b3-lakehouse-aws-bronze-runs"
    "--database"                     = "b3_lakehouse_silver"
    "--extra-py-files"               = "s3://${local.bucket}/scripts/history-libs.zip"
    "--datalake-formats"             = "iceberg"
    "--job-bookmark-option"          = "job-bookmark-disable"
    "--enable-auto-scaling"          = "false"
    "--enable-metrics"               = "false"
    "--enable-observability-metrics" = "false"
    "--custom-logGroup-prefix"       = "/b3-lakehouse-aws/history-2025"
    "--TempDir"                      = "s3://${local.bucket}/temp/history/"
    "--conf" = join(" --conf ", [
      "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
      "spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog",
      "spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog",
      "spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO",
      "spark.sql.catalog.glue_catalog.warehouse=s3://${local.bucket}/silver/",
      "spark.sql.catalog.glue_catalog.s3.sse.type=s3",
      "spark.sql.shuffle.partitions=2"
    ])
  }
  depends_on = [aws_iam_role_policy.glue, aws_cloudwatch_log_group.history]
}
output "job_name" { value = aws_glue_job.history.name }
