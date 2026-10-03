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
  region = "sa-east-1"
  
  default_tags {
    tags = {
      Environment = "prod"
      Project     = "seguros-horizonte"
      ManagedBy   = "Terraform"
      Owner       = "Flavio"
      CreatedAt   = "2026-10"
    }
  }
}