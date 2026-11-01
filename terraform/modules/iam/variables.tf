variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "seguros-horizonte"
}

variable "aws_region" {
  description = "Região usada para montar os ARNs (logs, RDS, Secrets Manager)"
  type        = string
  default     = "sa-east-1"
}

# ==========================================
# FASE 7: ARNs exatos (substituem curingas)
# ==========================================

variable "app_bucket_arns" {
  description = "ARNs dos buckets que a aplicação acessa (vêm do módulo storage)"
  type        = list(string)
}

variable "s3_kms_key_arn" {
  description = "ARN da chave KMS dos buckets (vem do módulo kms)"
  type        = string
}
