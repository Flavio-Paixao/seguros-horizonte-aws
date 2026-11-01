# ==========================================
# Module: Networking (VPC em 2 AZs)
# ==========================================

module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  vpc_cidr             = "10.0.0.0/16"
  azs                  = ["sa-east-1a", "sa-east-1b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
}

# ==========================================
# Module: IAM (roles da EC2, RDS monitoring e Lambda)
# ==========================================

module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  environment  = var.environment
}
