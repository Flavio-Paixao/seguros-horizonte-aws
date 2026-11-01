# ==========================================
# OUTPUTS DA RAIZ
# ==========================================

output "rds_kms_key_arn" {
  description = "ARN da chave KMS do banco"
  value       = module.kms.rds_key_arn
}

output "s3_kms_key_arn" {
  description = "ARN da chave KMS do S3 (usada na Fase 7)"
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
