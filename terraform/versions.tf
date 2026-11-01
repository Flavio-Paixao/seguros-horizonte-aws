terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.20"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Tags aplicadas automaticamente em TODO recurso que aceita tags
  default_tags {
    tags = {
      Environment = var.environment # L7: a variável agora é usada de verdade
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Owner       = "Flavio"
      Repository  = "github.com/Flavio-Paixao/seguros-horizonte"
    }
  }
}
