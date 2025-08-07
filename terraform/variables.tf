# In this file put the variables related to the deployment
variable "environment" {
  type = string
  description = "Environment name"
  validation {
    condition = contains(["devel", "stage", "prod"], var.environment)
    error_message = "Environment must be one of: devel, stage, prod."
  }
}

variable "project" {
  type = string
  description = "Project name"
}
