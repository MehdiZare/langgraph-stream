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
