terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
}
variable "account_id" { type = string }
variable "region" { type = string }
variable "task_boundary_arn" { type = string }
variable "execution_boundary_arn" { type = string }
variable "image_digest" {
  type    = string
  default = null
  validation {
    condition     = var.image_digest == null || can(regex("^sha256:[0-9a-f]{64}$", var.image_digest))
    error_message = "Use a reviewed immutable ECR digest, never a mutable image tag."
  }
}
locals {
  name = "b3-lakehouse-aws-gold"
  tags = { Project = "b3-lakehouse-aws", ManagedBy = "Terraform" }
}
resource "aws_s3_bucket" "gold" {
  bucket        = "${local.name}-${var.account_id}"
  force_destroy = false
  tags          = local.tags
}
resource "aws_s3_bucket_public_access_block" "gold" {
  bucket                  = aws_s3_bucket.gold.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "gold" {
  bucket = aws_s3_bucket.gold.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "gold" {
  bucket = aws_s3_bucket.gold.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.gold.arn, "${aws_s3_bucket.gold.arn}/*"]
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }] })
  depends_on = [aws_s3_bucket_public_access_block.gold]
}
resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.gold.id
  rule {
    id     = "expire-query-results-only"
    status = "Enabled"
    filter { prefix = "athena-results/" }
    expiration { days = 1 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}
resource "aws_athena_workgroup" "gold" {
  name          = local.name
  force_destroy = false
  tags          = local.tags
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = 1073741824
    engine_version { selected_engine_version = "Athena engine version 3" }
    result_configuration {
      output_location = "s3://${aws_s3_bucket.gold.id}/athena-results/"
      encryption_configuration { encryption_option = "SSE_S3" }
    }
  }
}
resource "aws_glue_catalog_database" "gold" {
  name       = "b3_lakehouse_gold"
  catalog_id = var.account_id
  create_table_default_permission {
    permissions = ["ALL"]
    principal { data_lake_principal_identifier = "IAM_ALLOWED_PRINCIPALS" }
  }
}
resource "aws_ecr_repository" "gold" {
  name                 = local.name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  tags                 = local.tags
  encryption_configuration { encryption_type = "AES256" }
}
resource "aws_ecr_lifecycle_policy" "gold" {
  repository = aws_ecr_repository.gold.name
  policy = jsonencode({ rules = [{ rulePriority = 1, description = "Remove untagged images after one day",
    selection = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 1 },
    action    = { type = "expire" }
  }] })
}
resource "aws_cloudwatch_log_group" "gold" {
  name              = "/b3-lakehouse-aws/gold"
  retention_in_days = 3
  tags              = local.tags
}
resource "aws_ecs_cluster" "gold" {
  name = local.name
  tags = local.tags
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}
resource "aws_vpc" "gold" {
  cidr_block           = "10.83.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = local.name })
}
resource "aws_subnet" "gold" {
  vpc_id                  = aws_vpc.gold.id
  cidr_block              = "10.83.0.0/26"
  map_public_ip_on_launch = false
  tags                    = merge(local.tags, { Name = local.name })
}
resource "aws_internet_gateway" "gold" {
  vpc_id = aws_vpc.gold.id
  tags   = local.tags
}
resource "aws_route_table" "gold" {
  vpc_id = aws_vpc.gold.id
  tags   = local.tags
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gold.id
  }
}
resource "aws_route_table_association" "gold" {
  subnet_id      = aws_subnet.gold.id
  route_table_id = aws_route_table.gold.id
}
resource "aws_security_group" "gold" {
  name        = local.name
  description = "No ingress; HTTPS egress for AWS APIs and ECR"
  vpc_id      = aws_vpc.gold.id
  tags        = local.tags
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_iam_role" "task" {
  name                 = "${local.name}-task"
  permissions_boundary = var.task_boundary_arn
  tags                 = local.tags
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ecs-tasks.amazonaws.com" }
  }] })
}
resource "aws_iam_role" "execution" {
  name                 = "${local.name}-execution"
  permissions_boundary = var.execution_boundary_arn
  tags                 = local.tags
  assume_role_policy   = aws_iam_role.task.assume_role_policy
}
resource "aws_iam_role_policy" "task" {
  role   = aws_iam_role.task.id
  name   = "gold-only"
  policy = templatefile("${path.module}/task-policy.json.tftpl", { account = var.account_id, region = var.region })
}
resource "aws_iam_role_policy" "execution" {
  role   = aws_iam_role.execution.id
  name   = "ecr-and-logs-only"
  policy = templatefile("${path.module}/execution-policy.json.tftpl", { account = var.account_id, region = var.region })
}
resource "aws_ecs_task_definition" "gold" {
  count                    = var.image_digest == null ? 0 : 1
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  task_role_arn            = aws_iam_role.task.arn
  execution_role_arn       = aws_iam_role.execution.arn
  tags                     = local.tags
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([{
    name = "dbt", image = "${aws_ecr_repository.gold.repository_url}@${var.image_digest}", essential = true,
    user = "10001", stopTimeout = 30,
    environment = [
      { name = "GOLD_DATABASE", value = aws_glue_catalog_database.gold.name },
      { name = "GOLD_DATA_URI", value = "s3://${aws_s3_bucket.gold.id}/gold/" },
      { name = "ATHENA_RESULTS_URI", value = "s3://${aws_s3_bucket.gold.id}/athena-results/" },
      { name = "ATHENA_WORKGROUP", value = aws_athena_workgroup.gold.name }
    ],
    logConfiguration = { logDriver = "awslogs", options = {
      "awslogs-group"  = aws_cloudwatch_log_group.gold.name,
      "awslogs-region" = var.region, "awslogs-stream-prefix" = "dbt"
    } }
  }])
}
output "repository_url" { value = aws_ecr_repository.gold.repository_url }
output "cluster_arn" { value = aws_ecs_cluster.gold.arn }
output "task_definition_arn" { value = try(aws_ecs_task_definition.gold[0].arn, null) }
output "network_configuration" {
  value = { awsvpcConfiguration = {
    subnets = [aws_subnet.gold.id], securityGroups = [aws_security_group.gold.id], assignPublicIp = "ENABLED"
  } }
}
