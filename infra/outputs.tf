# Outputs for LangGraph WebSocket Infrastructure

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer (use for Cloudflare CNAME)"
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "Full URL to access the application"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  description = "ECR repository URL for pushing Docker images"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app.name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.app.name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "secrets_to_update" {
  description = "Secrets that need to be updated with real values"
  value = {
    llama_api_key = aws_secretsmanager_secret.llama_api_key.name
    steel_api_key = aws_secretsmanager_secret.steel_api_key.name
    serpapi_key   = aws_secretsmanager_secret.serpapi_key.name
  }
}

output "docker_build_commands" {
  description = "Commands to build and push Docker image"
  value = <<-EOT
    # Login to ECR
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.app.repository_url}

    # Build image
    docker build -t ${var.project_name}:${var.app_image_tag} .

    # Tag image
    docker tag ${var.project_name}:${var.app_image_tag} ${aws_ecr_repository.app.repository_url}:${var.app_image_tag}

    # Push image
    docker push ${aws_ecr_repository.app.repository_url}:${var.app_image_tag}
  EOT
}

output "update_secrets_commands" {
  description = "Commands to update secrets with real API keys"
  value = <<-EOT
    # Update Llama API Key
    aws secretsmanager update-secret --secret-id ${aws_secretsmanager_secret.llama_api_key.name} --secret-string "YOUR_LLAMA_API_KEY" --region ${var.aws_region}

    # Update Steel API Key
    aws secretsmanager update-secret --secret-id ${aws_secretsmanager_secret.steel_api_key.name} --secret-string "YOUR_STEEL_API_KEY" --region ${var.aws_region}

    # Update SerpAPI Key
    aws secretsmanager update-secret --secret-id ${aws_secretsmanager_secret.serpapi_key.name} --secret-string "YOUR_SERPAPI_KEY" --region ${var.aws_region}
  EOT
}

output "cloudflare_cname_config" {
  description = "Cloudflare DNS configuration"
  value = {
    type    = "CNAME"
    name    = "your-subdomain"
    content = aws_lb.main.dns_name
    proxied = false
  }
}

output "vercel_env_var_set" {
  description = "Confirmation that Vercel environment variable was set"
  value = {
    variable_name = "NEXT_PUBLIC_WEBSOCKET_URL"
    value         = "http://${aws_lb.main.dns_name}"
    environments  = ["production", "preview", "development"]
    project_id    = var.vercel_project_id
  }
}

output "vercel_redeploy_instructions" {
  description = "Instructions to redeploy Vercel to pick up new env var"
  value       = "Run: vercel --prod (or trigger redeploy in Vercel UI)"
}
