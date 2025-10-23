variable "service_name" {
  description = "Name of the service (e.g., roboad-backend-prod, roboad-backend-pr-123)"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, pr-123, etc.)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

# Networking
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

# Container Configuration
variable "container_image" {
  description = "Docker image to deploy"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8010
}

# ECS Task Configuration
variable "task_cpu" {
  description = "CPU units for ECS task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Memory for ECS task in MB"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
}

# IAM Roles
variable "task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role"
  type        = string
}

# Secrets
variable "llama_api_key_secret_arn" {
  description = "ARN of the Llama API key secret"
  type        = string
}

variable "steel_api_key_secret_arn" {
  description = "ARN of the Steel API key secret"
  type        = string
}

variable "serpapi_key_secret_arn" {
  description = "ARN of the SerpAPI key secret"
  type        = string
}

# CloudWatch
variable "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  type        = string
}

# ALB Configuration
variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds (important for WebSocket)"
  type        = number
  default     = 300
}

# Auto Scaling
variable "enable_autoscaling" {
  description = "Enable auto scaling"
  type        = bool
  default     = false
}

variable "autoscaling_min_capacity" {
  description = "Minimum number of ECS tasks for auto-scaling"
  type        = number
  default     = 1
}

variable "autoscaling_max_capacity" {
  description = "Maximum number of ECS tasks for auto-scaling"
  type        = number
  default     = 4
}

variable "autoscaling_cpu_target" {
  description = "Target CPU utilization percentage for auto-scaling"
  type        = number
  default     = 70
}

# Monitoring
variable "enable_container_insights" {
  description = "Enable ECS Container Insights"
  type        = bool
  default     = false
}

# Additional Configuration
variable "additional_environment_variables" {
  description = "Additional environment variables for the container"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
