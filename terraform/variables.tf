# ==========================================
# VARIÁVEIS DA RAIZ
# ==========================================

variable "aws_region" {
  description = "Região AWS (São Paulo: latência e residência de dados para LGPD)"
  type        = string
  default     = "sa-east-1"
}

variable "project_name" {
  description = "Nome do projeto (prefixo de todos os recursos)"
  type        = string
  default     = "seguros-horizonte"
}

variable "environment" {
  description = "Ambiente (prod, staging, dev)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment deve ser prod, staging ou dev."
  }
}
