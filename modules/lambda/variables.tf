variable "project_name" {
  type = string
}

variable "log_group_arn" {
  type = string
}

variable "log_group_name" {
  type = string
}

variable "teams_webhook_login" {
  type      = string
  sensitive = true
}

variable "teams_webhook_delete" {
  type      = string
  sensitive = true
}