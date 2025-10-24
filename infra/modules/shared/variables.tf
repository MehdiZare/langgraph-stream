variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "llama_api_key" {
  description = "Llama API key"
  type        = string
  sensitive   = true
}

variable "steel_api_key" {
  description = "Steel.dev API key"
  type        = string
  sensitive   = true
}

variable "serpapi_key" {
  description = "SerpAPI key"
  type        = string
  sensitive   = true
}

variable "clerk_secret_key" {
  description = "Clerk secret key for authentication"
  type        = string
  sensitive   = true
}

variable "clerk_publishable_key" {
  description = "Clerk publishable key"
  type        = string
  sensitive   = true
}

variable "supabase_url" {
  description = "Supabase project URL"
  type        = string
  sensitive   = true
}

variable "supabase_anon_key" {
  description = "Supabase anonymous key"
  type        = string
  sensitive   = true
}

variable "supabase_service_role_key" {
  description = "Supabase service role key"
  type        = string
  sensitive   = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
