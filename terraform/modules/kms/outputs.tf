output "rds_key_arn" {
  description = "ARN da chave KMS do RDS"
  value       = aws_kms_key.rds.arn
}

output "s3_key_arn" {
  description = "ARN da chave KMS do S3"
  value       = aws_kms_key.s3.arn
}
