# Outputs - valores pra usar em outros módulos

output "vpc_id" {
  description = "ID da VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block da VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "ID da subnet pública"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID da subnet privada"
  value       = aws_subnet.private.id
}

output "alb_security_group_id" {
  description = "ID do security group do ALB"
  value       = aws_security_group.alb.id
}

output "rds_security_group_id" {
  description = "ID do security group do RDS"
  value       = aws_security_group.rds.id
}

output "nat_gateway_id" {
  description = "ID do NAT Gateway"
  value       = aws_nat_gateway.main.id
}