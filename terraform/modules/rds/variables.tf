variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "seguros-horizonte"
}

variable "private_subnet_ids" {
  description = "IDs das subnets privadas (pelo menos 2, em AZs diferentes)"
  type        = list(string)
}

variable "azs" {
  description = "AZs da primária e da réplica, nesta ordem (writer na 1a, reader na 1b)"
  type        = list(string)
  default     = ["sa-east-1a", "sa-east-1b"]
}

variable "rds_security_group_id" {
  description = "ID do security group do banco"
  type        = string
}

variable "rds_monitoring_role_arn" {
  description = "ARN da role de Enhanced Monitoring (criada na Fase 4)"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN da chave KMS que criptografa o banco"
  type        = string
}

variable "db_name" {
  description = "Nome do banco de dados"
  type        = string
  default     = "segurosdb"
}

variable "db_username" {
  description = "Usuário administrador (a SENHA é gerada pela AWS)"
  type        = string
  default     = "postgresadmin"
}

variable "instance_class" {
  description = "Classe das instâncias (db.t3.medium é a menor do Aurora PostgreSQL)"
  type        = string
  default     = "db.t3.medium"
}
