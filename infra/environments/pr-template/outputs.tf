output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.ecs_service.alb_dns_name
}

output "alb_url" {
  description = "Full service URL with HTTPS (via Cloudflare SSL)"
  value       = module.ecs_service.service_url
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

# Vercel outputs disabled - integration removed (backend/frontend in separate repos)
# Manage Vercel environment variables separately in Vercel dashboard

# output "vercel_env_vars_created" {
#   description = "Whether Vercel environment variables were created"
#   value       = length(vercel_project_environment_variable.backend_url) > 0
# }

# output "vercel_project_id" {
#   description = "Vercel project ID (if configured)"
#   value       = var.vercel_project_id
# }

# output "vercel_preview_url" {
#   description = "Vercel preview deployment URL"
#   value       = try(vercel_deployment.pr_preview[0].url, "pending")
# }
