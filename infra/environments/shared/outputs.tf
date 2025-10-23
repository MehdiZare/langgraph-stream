output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = module.networking.private_subnet_ids
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = module.shared.ecr_repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = module.shared.ecr_repository_name
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = module.shared.ecs_task_execution_role_arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = module.shared.ecs_task_role_arn
}

output "llama_api_key_secret_arn" {
  description = "ARN of the Llama API key secret"
  value       = module.shared.llama_api_key_secret_arn
}

output "steel_api_key_secret_arn" {
  description = "ARN of the Steel API key secret"
  value       = module.shared.steel_api_key_secret_arn
}

output "serpapi_key_secret_arn" {
  description = "ARN of the SerpAPI key secret"
  value       = module.shared.serpapi_key_secret_arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = module.shared.cloudwatch_log_group_name
}
