terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {}
}
variable "account_id" { type = string }
variable "region" {
  type    = string
  default = "us-east-1"
}
variable "alert_email" {
  type      = string
  sensitive = true
}
variable "project_start" { type = string }
variable "project_end" { type = string }

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags { tags = { Project = "b3-lakehouse-aws", ManagedBy = "Terraform" } }
}
module "budget" {
  source          = "../../modules/budget"
  account_id      = var.account_id
  alert_email     = var.alert_email
  project_start   = var.project_start
  project_end     = var.project_end
  total_limit_usd = 10
}
