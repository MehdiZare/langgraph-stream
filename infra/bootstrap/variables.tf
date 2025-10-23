variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Project name (used in resource naming)"
  type        = string
  default     = "roboad-backend"
}

variable "iam_user_name" {
  description = "Name of the IAM user for automation"
  type        = string
  default     = "github-terraform-deployer"
}
