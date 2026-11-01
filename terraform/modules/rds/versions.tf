# Versões exigidas por este módulo (o tflint cobra isso em cada módulo)
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.20"
    }
  }
}
