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

variable "clerk_secret_key" {
  description = "Clerk secret key for NON-PRODUCTION environments (dev, preview, PR). Production uses separate credentials. (set in Terraform Cloud as sensitive variable)"
  type        = string
  sensitive   = true
}

variable "clerk_publishable_key" {
  description = "Clerk publishable key for NON-PRODUCTION environments (dev, preview, PR). Production uses separate credentials. (set in Terraform Cloud as sensitive variable)"
  type        = string
  sensitive   = true
}

variable "supabase_url" {
  description = "Supabase project URL (set in Terraform Cloud as sensitive variable)"
  type        = string
  sensitive   = true
}

variable "supabase_anon_key" {
  description = "Supabase anonymous key (set in Terraform Cloud as sensitive variable)"
  type        = string
  sensitive   = true
}

variable "supabase_service_role_key" {
  description = "Supabase service role key (set in Terraform Cloud as sensitive variable)"
  type        = string
  sensitive   = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}
