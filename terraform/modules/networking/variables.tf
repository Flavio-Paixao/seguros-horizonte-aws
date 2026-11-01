# ==========================================
# VARIÁVEIS DA REDE
# ==========================================

variable "project_name" {
  description = "Nome do projeto (prefixo dos nomes)"
  type        = string
  default     = "seguros-horizonte"
}

variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Zonas de disponibilidade usadas (2, para alta disponibilidade)"
  type        = list(string)
  default     = ["sa-east-1a", "sa-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas (uma por AZ, na mesma ordem de azs)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas (uma por AZ, na mesma ordem de azs)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "app_port" {
  description = "Porta em que a aplicação escuta nas instâncias EC2"
  type        = number
  default     = 8000
}

variable "db_port" {
  description = "Porta do PostgreSQL"
  type        = number
  default     = 5432
}
