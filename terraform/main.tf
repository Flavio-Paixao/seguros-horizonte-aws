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
  aws_region   = var.aws_region

  # Fase 7: ARNs exatos no lugar dos curingas
  app_bucket_arns = module.storage.bucket_arns
  s3_kms_key_arn  = module.kms.s3_key_arn
}

# ==========================================
# Module: KMS (chave do banco e chave do S3)
# ==========================================

module "kms" {
  source = "./modules/kms"

  project_name = var.project_name
}

# ==========================================
# Module: RDS (Aurora PostgreSQL em 2 AZs)
# ==========================================

module "rds" {
  source = "./modules/rds"

  project_name            = var.project_name
  azs                     = ["sa-east-1a", "sa-east-1b"]
  private_subnet_ids      = module.networking.private_subnet_ids
  rds_security_group_id   = module.networking.rds_security_group_id
  rds_monitoring_role_arn = module.iam.rds_monitoring_role_arn
  kms_key_arn             = module.kms.rds_key_arn

  db_name        = "segurosdb"
  db_username    = "postgresadmin"
  instance_class = "db.t3.medium"
}

# ==========================================
# Module: EC2 (ALB + Launch Template + Auto Scaling)
# ==========================================

module "ec2" {
  source = "./modules/ec2"

  project_name             = var.project_name
  vpc_id                   = module.networking.vpc_id
  public_subnet_ids        = module.networking.public_subnet_ids
  private_subnet_ids       = module.networking.private_subnet_ids
  alb_security_group_id    = module.networking.alb_security_group_id
  app_security_group_id    = module.networking.app_security_group_id
  ec2_instance_profile_arn = module.iam.ec2_instance_profile_arn

  instance_type        = "t3.small"
  asg_min_size         = 2 # uma instância por AZ, sempre
  asg_max_size         = 4
  asg_desired_capacity = 2
}

# ==========================================
# Module: Storage (3 buckets S3 com SSE-KMS)
# ==========================================

module "storage" {
  source = "./modules/storage"

  project_name          = var.project_name
  kms_key_arn           = module.kms.s3_key_arn
  backup_retention_days = 30
  log_retention_days    = 2555
}
