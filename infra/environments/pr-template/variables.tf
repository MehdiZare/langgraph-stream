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

variable "pr_number" {
  description = "GitHub Pull Request number"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8010
}

# ECS Configuration - Smaller resources for PR environments
variable "ecs_task_cpu" {
  description = "CPU units for ECS task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256  # Smaller than prod
}

variable "ecs_task_memory" {
  description = "Memory for ECS task in MB"
  type        = number
  default     = 512  # Smaller than prod
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1  # Single task for PR environments
}

# ALB Configuration
variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds (important for WebSocket)"
  type        = number
  default     = 300
}
