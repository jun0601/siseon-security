variable "project_name" {
  description = "프로젝트 이름"
  type        = string
}

variable "resource_group_name" {
  description = "Azure 리소스 그룹 이름"
  type        = string
}

variable "location" {
  description = "Azure 리전"
  type        = string
}

variable "azure_connection_string" {
  description = "Azure Blob Storage 연결 문자열"
  type        = string
  sensitive   = true
}