# Variáveis da VPC

variable "vpc_cidr" {
  description = "CIDR block para a VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block para subnet pública"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block para subnet privada"
  type        = string
  default     = "10.0.2.0/24"
}

variable "environment" {
  description = "Ambiente (prod, staging, dev)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "seguros-horizonte"
}