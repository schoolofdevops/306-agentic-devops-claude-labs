output "asg_name" {
  description = "Name of the application autoscaling group."
  value       = aws_autoscaling_group.app.name
}

output "lb_dns_name" {
  description = "DNS name of the application load balancer."
  value       = aws_lb.app.dns_name
}

output "lb_arn" {
  description = "ARN of the application load balancer."
  value       = aws_lb.app.arn
}

output "target_group_arn" {
  description = "ARN of the application target group."
  value       = aws_lb_target_group.app.arn
}
