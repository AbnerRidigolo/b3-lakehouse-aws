variable "enable_silver" {
  type    = bool
  default = false
  validation {
    condition     = !var.enable_silver || var.enable_bronze
    error_message = "Silver requires the approved bronze module."
  }
}
module "silver" {
  count                    = var.enable_silver ? 1 : 0
  source                   = "../../modules/silver"
  account_id               = var.account_id
  region                   = var.region
  bronze_bucket            = module.bronze[0].bucket_name
  runs_table               = module.bronze[0].runs_table
  permissions_boundary_arn = "arn:aws:iam::${var.account_id}:policy/b3-lakehouse-aws-silver-boundary"
}
