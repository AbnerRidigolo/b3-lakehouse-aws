variable "enable_history" {
  type    = bool
  default = false
  validation {
    condition     = !var.enable_history || (var.enable_silver && var.enable_bronze)
    error_message = "Historical processing requires the deployed silver and bronze."
  }
}
variable "history_emr_enabled" {
  type    = bool
  default = true
}
variable "enable_history_glue" {
  type    = bool
  default = false
  validation {
    condition     = !var.enable_history_glue || (var.enable_history && !var.history_emr_enabled)
    error_message = "Glue history requires preserved history artifacts and disabled EMR."
  }
}
module "history" {
  count                    = var.enable_history ? 1 : 0
  source                   = "../../modules/history"
  account_id               = var.account_id
  region                   = var.region
  permissions_boundary_arn = "arn:aws:iam::${var.account_id}:policy/b3-lakehouse-aws-history-2025-boundary"
  emr_enabled              = var.history_emr_enabled
  depends_on               = [module.silver]
}
module "history_glue" {
  count                    = var.enable_history_glue ? 1 : 0
  source                   = "../../modules/history-glue"
  account_id               = var.account_id
  region                   = var.region
  permissions_boundary_arn = "arn:aws:iam::${var.account_id}:policy/b3-lakehouse-aws-history-2025-boundary"
  depends_on               = [module.history]
}
output "history_glue_job_name" { value = try(module.history_glue[0].job_name, null) }
output "history_application_id" { value = try(module.history[0].application_id, null) }
output "history_role_arn" { value = try(module.history[0].role_arn, null) }
