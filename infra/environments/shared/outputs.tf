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

output "clerk_secret_key_arn" {
  description = "ARN of the Clerk secret key"
  value       = module.shared.clerk_secret_key_arn
}

output "clerk_publishable_key_arn" {
  description = "ARN of the Clerk publishable key"
  value       = module.shared.clerk_publishable_key_arn
}

output "supabase_url_secret_arn" {
  description = "ARN of the Supabase URL secret"
  value       = module.shared.supabase_url_secret_arn
}

output "supabase_anon_key_secret_arn" {
  description = "ARN of the Supabase anon key secret"
  value       = module.shared.supabase_anon_key_secret_arn
}

output "supabase_service_role_key_secret_arn" {
  description = "ARN of the Supabase service role key secret"
  value       = module.shared.supabase_service_role_key_secret_arn
}

output "s3_scans_bucket_name" {
  description = "Name of the S3 bucket for scan data"
  value       = module.shared.s3_scans_bucket_name
}

output "s3_scans_bucket_arn" {
  description = "ARN of the S3 bucket for scan data"
  value       = module.shared.s3_scans_bucket_arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = module.shared.cloudwatch_log_group_name
}
