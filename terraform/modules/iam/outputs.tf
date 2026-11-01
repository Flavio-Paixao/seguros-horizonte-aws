output "ec2_role_id" {
  description = "ID da role EC2"
  value       = aws_iam_role.ec2_role.id
}

output "ec2_role_arn" {
  description = "ARN da role EC2"
  value       = aws_iam_role.ec2_role.arn
}

output "ec2_instance_profile_arn" {
  description = "ARN do instance profile EC2"
  value       = aws_iam_instance_profile.ec2_profile.arn
}

output "rds_monitoring_role_arn" {
  description = "ARN da role RDS monitoring"
  value       = aws_iam_role.rds_monitoring_role.arn
}

output "lambda_role_arn" {
  description = "ARN da role Lambda"
  value       = aws_iam_role.lambda_role.arn
}