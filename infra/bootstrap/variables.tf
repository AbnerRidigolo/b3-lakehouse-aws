variable "account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Use a 12-digit AWS account ID."
  }
}
variable "region" {
  type    = string
  default = "us-east-1"
  validation {
    condition     = contains(["us-east-1", "us-east-2"], var.region)
    error_message = "Only the proposed region or Ohio is allowed."
  }
}
variable "state_bucket_name" {
  type = string
  validation {
    condition     = can(regex("^b3-lakehouse-aws-[a-z0-9-]+$", var.state_bucket_name)) && length(var.state_bucket_name) <= 63
    error_message = "Use a globally unique b3-lakehouse-aws-* bucket name, at most 63 characters."
  }
}
variable "existing_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN, or null to create one after checking the account."
  type        = string
  default     = null
}
