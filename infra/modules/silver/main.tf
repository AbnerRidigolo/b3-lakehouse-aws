terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
}
variable "account_id" { type = string }
variable "region" { type = string }
variable "bronze_bucket" { type = string }
variable "runs_table" { type = string }
variable "permissions_boundary_arn" { type = string }
locals {
  name     = "b3-lakehouse-aws-silver"
  database = "b3_lakehouse_silver"
  catalog_arns = [
    "arn:aws:glue:${var.region}:${var.account_id}:catalog",
    "arn:aws:glue:${var.region}:${var.account_id}:database/${local.database}",
    "arn:aws:glue:${var.region}:${var.account_id}:table/${local.database}/b3_daily",
    "arn:aws:glue:${var.region}:${var.account_id}:table/${local.database}/bcb_daily"
  ]
}
resource "aws_s3_bucket" "data" {
  bucket        = "${local.name}-${var.account_id}"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "data" {
  bucket = aws_s3_bucket.data.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Deny", Principal = "*", Action = "s3:*"
    Resource  = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/*"]
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }] })
  depends_on = [aws_s3_bucket_public_access_block.data]
}
resource "aws_s3_bucket_lifecycle_configuration" "temp" {
  bucket = aws_s3_bucket.data.id
  rule {
    id     = "temporary-files-only"
    status = "Enabled"
    filter { prefix = "temp/" }
    expiration { days = 1 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}
resource "aws_s3_object" "script" {
  bucket                 = aws_s3_bucket.data.id
  key                    = "scripts/silver-job.py"
  source                 = "${path.module}/../../../artifacts/silver-job.py"
  source_hash            = filesha256("${path.module}/../../../artifacts/silver-job.py")
  server_side_encryption = "AES256"
}
resource "aws_s3_object" "libs" {
  bucket                 = aws_s3_bucket.data.id
  key                    = "scripts/silver-libs.zip"
  source                 = "${path.module}/../../../artifacts/silver-libs.zip"
  source_hash            = filesha256("${path.module}/../../../artifacts/silver-libs.zip")
  server_side_encryption = "AES256"
}
resource "aws_glue_catalog_database" "silver" {
  name       = local.database
  catalog_id = var.account_id
  # Use IAM authorization. No Lake Formation registration or paid optimizer.
  create_table_default_permission {
    permissions = ["ALL"]
    principal { data_lake_principal_identifier = "IAM_ALLOWED_PRINCIPALS" }
  }
}
resource "aws_cloudwatch_log_group" "silver" {
  for_each          = toset(["error", "output"])
  name              = "/b3-lakehouse-aws/silver/${each.key}"
  retention_in_days = 3
}
resource "aws_iam_role" "glue" {
  name                 = local.name
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Service = "glue.amazonaws.com" }, Action = "sts:AssumeRole"
  }] })
}
resource "aws_iam_role_policy" "glue" {
  name = "silver-only"
  role = aws_iam_role.glue.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetObject"], Resource = "arn:aws:s3:::${var.bronze_bucket}/bronze/*" },
    { Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation"], Resource = ["arn:aws:s3:::${var.bronze_bucket}", aws_s3_bucket.data.arn] },
    { Effect = "Allow", Action = "s3:GetObject", Resource = "${aws_s3_bucket.data.arn}/scripts/*" },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"], Resource = ["${aws_s3_bucket.data.arn}/silver/*", "${aws_s3_bucket.data.arn}/temp/*"] },
    { Effect = "Allow", Action = ["glue:GetDatabase", "glue:GetTable", "glue:CreateTable", "glue:UpdateTable"], Resource = local.catalog_arns },
    { Effect = "Allow", Action = "glue:GetJobBookmark", Resource = "arn:aws:glue:${var.region}:${var.account_id}:job/${local.name}" },
    { Effect = "Allow", Action = "dynamodb:GetItem", Resource = "arn:aws:dynamodb:${var.region}:${var.account_id}:table/${var.runs_table}", Condition = { "ForAllValues:StringLike" = { "dynamodb:LeadingKeys" = ["bronze#*", "silver#*"] } } },
    { Effect = "Allow", Action = "dynamodb:UpdateItem", Resource = "arn:aws:dynamodb:${var.region}:${var.account_id}:table/${var.runs_table}", Condition = { "ForAllValues:StringLike" = { "dynamodb:LeadingKeys" = ["silver#*"] } } },
    { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = [for g in aws_cloudwatch_log_group.silver : "${g.arn}:*"] }
  ] })
}
resource "aws_glue_job" "silver" {
  name              = local.name
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 10
  max_retries       = 0
  execution_class   = "STANDARD"
  execution_property { max_concurrent_runs = 1 }
  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.data.id}/${aws_s3_object.script.key}"
  }
  non_overridable_arguments = {
    "--datalake-formats"             = "iceberg"
    "--extra-py-files"               = "s3://${aws_s3_bucket.data.id}/${aws_s3_object.libs.key}"
    "--bronze_bucket"                = var.bronze_bucket
    "--silver_bucket"                = aws_s3_bucket.data.id
    "--runs_table"                   = var.runs_table
    "--database"                     = local.database
    "--job-bookmark-option"          = "job-bookmark-disable"
    "--enable-auto-scaling"          = "false"
    "--enable-metrics"               = "false"
    "--enable-observability-metrics" = "false"
    "--custom-logGroup-prefix"       = "/b3-lakehouse-aws/silver"
    "--TempDir"                      = "s3://${aws_s3_bucket.data.id}/temp/"
    "--conf" = join(" --conf ", [
      "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
      "spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog",
      "spark.sql.catalog.glue_catalog.warehouse=s3://${aws_s3_bucket.data.id}/silver/",
      "spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog",
      "spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO",
      "spark.sql.catalog.glue_catalog.s3.sse.type=s3",
      "spark.sql.shuffle.partitions=2"
    ])
  }
  depends_on = [aws_iam_role_policy.glue, aws_cloudwatch_log_group.silver, aws_glue_catalog_database.silver]
}
output "job_name" { value = aws_glue_job.silver.name }
output "bucket_name" { value = aws_s3_bucket.data.id }
output "database_name" { value = aws_glue_catalog_database.silver.name }
