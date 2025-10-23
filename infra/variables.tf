# Variables for LangGraph WebSocket Infrastructure

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

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "production"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
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
  default     = 1
}

variable "ecs_min_capacity" {
  description = "Minimum number of ECS tasks for auto-scaling"
  type        = number
  default     = 1
}

variable "ecs_max_capacity" {
  description = "Maximum number of ECS tasks for auto-scaling"
  type        = number
  default     = 4
}

variable "ecs_cpu_target" {
  description = "Target CPU utilization percentage for auto-scaling"
  type        = number
  default     = 70
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8010
}

# Application Configuration
variable "app_image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

# ALB Configuration
variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds (important for WebSocket)"
  type        = number
  default     = 300
}

# Secrets (set these in Terraform Cloud as sensitive variables)
variable "llama_api_key" {
  description = "Llama API key (set in Terraform Cloud as sensitive variable)"
  type        = string
  sensitive   = true
}

variable "steel_api_key" {
  description = "Steel.dev API key (set in Terraform Cloud as sensitive variable)"
  type        = string
  sensitive   = true
}

variable "serpapi_key" {
  description = "SerpAPI key (set in Terraform Cloud as sensitive variable)"
  type        = string
  sensitive   = true
}

# Vercel Integration
variable "vercel_project_id" {
  description = "Vercel project ID (found in Project Settings → General)"
  type        = string
}

variable "vercel_team_id" {
  description = "Vercel team ID (optional, only for team projects)"
  type        = string
  default     = null
}
