variable "enable_gold" {
  type    = bool
  default = false
  validation {
    condition     = !var.enable_gold || var.enable_silver
    error_message = "Gold requires the deployed silver."
  }
}
variable "gold_image_digest" {
  type    = string
  default = null
}
module "gold" {
  count                  = var.enable_gold ? 1 : 0
  source                 = "../../modules/gold"
  account_id             = var.account_id
  region                 = var.region
  task_boundary_arn      = "arn:aws:iam::${var.account_id}:policy/b3-lakehouse-aws-gold-task-boundary"
  execution_boundary_arn = "arn:aws:iam::${var.account_id}:policy/b3-lakehouse-aws-gold-execution-boundary"
  image_digest           = var.gold_image_digest == "" ? null : var.gold_image_digest
  depends_on             = [module.silver]
}
output "gold_repository_url" { value = try(module.gold[0].repository_url, null) }
output "gold_cluster_arn" { value = try(module.gold[0].cluster_arn, null) }
output "gold_task_definition_arn" { value = try(module.gold[0].task_definition_arn, null) }
output "gold_network_configuration" { value = try(module.gold[0].network_configuration, null) }
