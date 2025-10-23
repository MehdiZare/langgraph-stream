output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.ecs_service.alb_dns_name
}

output "alb_url" {
  description = "URL of the Application Load Balancer"
  value       = "http://${module.ecs_service.alb_dns_name}"
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_service.ecs_cluster_name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = module.ecs_service.ecs_service_name
}

output "pr_number" {
  description = "GitHub Pull Request number"
  value       = var.pr_number
}

output "vercel_env_vars_created" {
  description = "Whether Vercel environment variables were created"
  value       = length(vercel_project_environment_variable.websocket_url) > 0
}

output "vercel_project_id" {
  description = "Vercel project ID (if configured)"
  value       = var.vercel_project_id
}
