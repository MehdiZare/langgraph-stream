output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.app.name
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_execution_role_name" {
  description = "Name of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.name
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task.arn
}

output "ecs_task_role_name" {
  description = "Name of the ECS task role"
  value       = aws_iam_role.ecs_task.name
}

output "llama_api_key_secret_arn" {
  description = "ARN of the Llama API key secret"
  value       = aws_secretsmanager_secret.llama_api_key.arn
}

output "steel_api_key_secret_arn" {
  description = "ARN of the Steel API key secret"
  value       = aws_secretsmanager_secret.steel_api_key.arn
}

output "serpapi_key_secret_arn" {
  description = "ARN of the SerpAPI key secret"
  value       = aws_secretsmanager_secret.serpapi_key.arn
}

output "clerk_secret_key_arn" {
  description = "ARN of the Clerk secret key"
  value       = aws_secretsmanager_secret.clerk_secret_key.arn
}

output "clerk_publishable_key_arn" {
  description = "ARN of the Clerk publishable key"
  value       = aws_secretsmanager_secret.clerk_publishable_key.arn
}

output "supabase_url_secret_arn" {
  description = "ARN of the Supabase URL secret"
  value       = aws_secretsmanager_secret.supabase_url.arn
}

output "supabase_anon_key_secret_arn" {
  description = "ARN of the Supabase anon key secret"
  value       = aws_secretsmanager_secret.supabase_anon_key.arn
}

output "supabase_service_role_key_secret_arn" {
  description = "ARN of the Supabase service role key secret"
  value       = aws_secretsmanager_secret.supabase_service_role_key.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.app.name
}

output "s3_scans_bucket_name" {
  description = "Name of the S3 bucket for scan data"
  value       = aws_s3_bucket.scans.id
}

output "s3_scans_bucket_arn" {
  description = "ARN of the S3 bucket for scan data"
  value       = aws_s3_bucket.scans.arn
}
