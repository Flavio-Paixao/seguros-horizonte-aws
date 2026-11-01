variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "seguros-horizonte"
}

variable "kms_key_arn" {
  description = "ARN da chave KMS que criptografa os buckets"
  type        = string
}

variable "backup_retention_days" {
  description = "Dias até apagar os backups"
  type        = number
  default     = 30
}

variable "log_retention_days" {
  description = "Dias até apagar os logs (2555 = 7 anos)"
  type        = number
  default     = 2555
}
