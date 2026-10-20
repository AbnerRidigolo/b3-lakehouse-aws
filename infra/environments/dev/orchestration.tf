variable "enable_orchestration" {
  type    = bool
  default = false
  validation {
    condition     = !var.enable_orchestration || (var.enable_gold && var.gold_image_digest != null && var.gold_image_digest != "")
    error_message = "Orchestration requires the deployed gold with a reviewed image digest."
  }
}
variable "orchestration_schedule_enabled" {
  type    = bool
  default = false
  validation {
    condition     = !var.orchestration_schedule_enabled || (var.enable_orchestration && !var.bronze_schedule_enabled)
    error_message = "The pipeline schedule replaces the direct bronze schedule; never enable both."
  }
}
module "orchestration" {
  count                      = var.enable_orchestration ? 1 : 0
  source                     = "../../modules/orchestration"
  account_id                 = var.account_id
  region                     = var.region
  sfn_boundary_arn           = "arn:aws:iam::${var.account_id}:policy/b3-lakehouse-aws-pipeline-sfn-boundary"
  scheduler_boundary_arn     = "arn:aws:iam::${var.account_id}:policy/b3-lakehouse-aws-pipeline-scheduler-boundary"
  alert_email                = var.alert_email
  bronze_function_name       = module.bronze[0].function_name
  silver_job_name            = module.silver[0].job_name
  runs_table                 = module.bronze[0].runs_table
  gold_cluster_arn           = module.gold[0].cluster_arn
  gold_task_definition_arn   = module.gold[0].task_definition_arn
  gold_network_configuration = module.gold[0].network_configuration
  schedule_enabled           = var.orchestration_schedule_enabled
}
output "pipeline_state_machine_arn" { value = try(module.orchestration[0].state_machine_arn, null) }
output "pipeline_dashboard_name" { value = try(module.orchestration[0].dashboard_name, null) }
