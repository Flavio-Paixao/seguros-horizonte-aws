output "cluster_id" {
  description = "ID do cluster Aurora"
  value       = aws_rds_cluster.aurora.id
}

output "cluster_endpoint" {
  description = "Endereço de escrita (primária)"
  value       = aws_rds_cluster.aurora.endpoint
}

output "cluster_reader_endpoint" {
  description = "Endereço de leitura (réplicas)"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "database_name" {
  description = "Nome do banco"
  value       = aws_rds_cluster.aurora.database_name
}

output "port" {
  description = "Porta do banco"
  value       = aws_rds_cluster.aurora.port
}

output "master_user_secret_arn" {
  description = "ARN do segredo (senha) no Secrets Manager"
  value       = aws_rds_cluster.aurora.master_user_secret[0].secret_arn
}
