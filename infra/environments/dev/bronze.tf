variable "enable_bronze" {
  type    = bool
  default = false
}
variable "bronze_schedule_enabled" {
  type    = bool
  default = false
}
module "bronze" {
  count                    = var.enable_bronze ? 1 : 0
  source                   = "../../modules/bronze"
  account_id               = var.account_id
  region                   = var.region
  lambda_zip               = "${path.root}/../../../artifacts/bronze.zip"
  permissions_boundary_arn = "arn:aws:iam::${var.account_id}:policy/b3-lakehouse-aws-bronze-boundary"
  schedule_enabled         = var.bronze_schedule_enabled
}
