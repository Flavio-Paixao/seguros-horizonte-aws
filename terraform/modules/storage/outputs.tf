output "app_data_bucket_name" {
  description = "Nome do bucket de dados da aplicação"
  value       = aws_s3_bucket.app_data.id
}

output "backups_bucket_name" {
  description = "Nome do bucket de backups"
  value       = aws_s3_bucket.backups.id
}

output "logs_bucket_name" {
  description = "Nome do bucket de logs"
  value       = aws_s3_bucket.logs.id
}

# Usado pelo módulo IAM para trocar o curinga "seguros-horizonte-*" pelos ARNs exatos
output "bucket_arns" {
  description = "ARNs dos 3 buckets (app-data, backups, logs)"
  value = [
    aws_s3_bucket.app_data.arn,
    aws_s3_bucket.backups.arn,
    aws_s3_bucket.logs.arn,
  ]
}
