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