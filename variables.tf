variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "account_id" {
  description = "AWS 계정 ID"
  type        = string
  default     = "448768137813"
}

variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  default     = "siseon"
}

variable "teams_webhook_login" {
  description = "Teams 로그인 알림 웹훅 URL"
  type        = string
  sensitive   = true
}

variable "teams_webhook_delete" {
  description = "Teams 삭제 알림 웹훅 URL"
  type        = string
  sensitive   = true
}

variable "teams_webhook_billing" {
  description = "Teams 빌링 알림 웹훅 URL"
  type        = string
  sensitive   = true
}

variable "azure_connection_string" {
  description = "Azure Blob Storage 연결 문자열"
  type        = string
  sensitive   = true
}

variable "azure_tenant_id" {
  description = "Azure 테넌트 ID"
  type        = string
  default     = "93985ad4-4ec6-4a22-a4bd-7a28a6294fd5"
}

variable "azure_subscription_id" {
  description = "Azure 구독 ID"
  type        = string
  default     = "41ba8281-70ed-41df-979f-13eef4480f49"
}

variable "azure_resource_group" {
  description = "Azure 리소스 그룹"
  type        = string
  default     = "siseon-rg"
}

variable "azure_location" {
  description = "Azure 리전"
  type        = string
  default     = "Korea Central"
}