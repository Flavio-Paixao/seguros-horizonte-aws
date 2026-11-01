# ==========================================
# OUTPUTS DA RAIZ
# ==========================================

output "vpc_id" {
  description = "ID da VPC"
  value       = module.networking.vpc_id
}

output "alb_dns_name" {
  description = "Endereço público do ALB (http://<este valor>/health)"
  value       = module.ec2.load_balancer_dns
}

output "asg_name" {
  description = "Nome do Auto Scaling Group"
  value       = module.ec2.asg_name
}

output "rds_kms_key_arn" {
  description = "ARN da chave KMS do banco"
  value       = module.kms.rds_key_arn
}

output "s3_kms_key_arn" {
  description = "ARN da chave KMS do S3 (criptografa os 3 buckets)"
  value       = module.kms.s3_key_arn
}

output "db_cluster_endpoint" {
  description = "Endereço de escrita do Aurora"
  value       = module.rds.cluster_endpoint
}

output "db_reader_endpoint" {
  description = "Endereço de leitura do Aurora"
  value       = module.rds.cluster_reader_endpoint
}

output "db_master_user_secret_arn" {
  description = "ARN do segredo da senha do banco (Secrets Manager)"
  value       = module.rds.master_user_secret_arn
}

output "app_data_bucket_name" {
  description = "Bucket de dados da aplicação"
  value       = module.storage.app_data_bucket_name
}

output "backups_bucket_name" {
  description = "Bucket de backups"
  value       = module.storage.backups_bucket_name
}

output "logs_bucket_name" {
  description = "Bucket de logs"
  value       = module.storage.logs_bucket_name
}
