variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "roboad-backend"
}

# Application Configuration
variable "app_image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8010
}

# ECS Configuration
variable "ecs_task_cpu" {
  description = "CPU units for ECS task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 512
}

variable "ecs_task_memory" {
  description = "Memory for ECS task in MB"
  type        = number
  default     = 1024
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "ecs_min_capacity" {
  description = "Minimum number of ECS tasks for auto-scaling"
  type        = number
  default     = 1
}

variable "ecs_max_capacity" {
  description = "Maximum number of ECS tasks for auto-scaling"
  type        = number
  default     = 10
}

variable "ecs_cpu_target" {
  description = "Target CPU utilization percentage for auto-scaling"
  type        = number
  default     = 70
}

# ALB Configuration
variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds (important for WebSocket)"
  type        = number
  default     = 300
}

# Monitoring
variable "enable_container_insights" {
  description = "Enable ECS Container Insights (additional cost)"
  type        = bool
  default     = false
}

# Production-specific Secrets
# Note: Preview/dev environments use separate Clerk instance from shared workspace
variable "clerk_secret_key_prod" {
  description = "Clerk secret key for PRODUCTION environment (set in Terraform Cloud as sensitive variable)"
  type        = string
  sensitive   = true
}

variable "clerk_publishable_key_prod" {
  description = "Clerk publishable key for PRODUCTION environment (set in Terraform Cloud as sensitive variable)"
  type        = string
  sensitive   = true
}

# Vercel Integration
variable "vercel_project_id" {
  description = "Vercel project ID (found in Project Settings → General)"
  type        = string
  default     = ""
}

variable "vercel_team_id" {
  description = "Vercel team ID (optional, only for team projects)"
  type        = string
  default     = null
}
