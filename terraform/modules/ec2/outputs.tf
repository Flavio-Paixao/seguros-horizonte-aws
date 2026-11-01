output "load_balancer_dns" {
  description = "Endereço (DNS) do ALB"
  value       = aws_lb.app.dns_name
}

output "asg_name" {
  description = "Nome do Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

output "target_group_arn" {
  description = "ARN do target group"
  value       = aws_lb_target_group.app.arn
}
