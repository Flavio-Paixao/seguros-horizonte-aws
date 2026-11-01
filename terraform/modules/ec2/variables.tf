variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "seguros-horizonte"
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets públicas do ALB (pelo menos 2, em AZs diferentes)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Subnets privadas das instâncias EC2"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ID do security group do ALB"
  type        = string
}

variable "app_security_group_id" {
  description = "ID do security group da aplicação (criado na rede)"
  type        = string
}

variable "ec2_instance_profile_arn" {
  description = "ARN do instance profile da EC2 (criado na Fase 4)"
  type        = string
}

variable "instance_type" {
  description = "Tipo de instância"
  type        = string
  default     = "t3.small"
}

variable "asg_min_size" {
  description = "Mínimo de instâncias (2 = uma por AZ, sobrevive à perda de uma AZ)"
  type        = number
  default     = 2

  validation {
    condition     = var.asg_min_size >= 2
    error_message = "Use pelo menos 2 instâncias para manter uma em cada AZ."
  }
}

variable "asg_max_size" {
  description = "Máximo de instâncias"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Quantidade desejada de instâncias"
  type        = number
  default     = 2
}
