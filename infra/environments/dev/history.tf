variable "enable_history" {
  type    = bool
  default = false
  validation {
    condition     = !var.enable_history || (var.enable_silver && var.enable_bronze)
    error_message = "Historical processing requires the deployed silver and bronze."
  }
}
module "history" {
  count                    = var.enable_history ? 1 : 0
  source                   = "../../modules/history"
  account_id               = var.account_id
  region                   = var.region
  permissions_boundary_arn = "arn:aws:iam::${var.account_id}:policy/b3-lakehouse-aws-history-2025-boundary"
  depends_on               = [module.silver]
}
output "history_application_id" { value = try(module.history[0].application_id, null) }
output "history_role_arn" { value = try(module.history[0].role_arn, null) }
