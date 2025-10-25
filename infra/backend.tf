# Terraform Cloud Backend Configuration
# This configuration uses Terraform Cloud for remote state management and execution

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    vercel = {
      source  = "vercel/vercel"
      version = "~> 3.0"
    }
  }

  # Terraform Cloud backend
  cloud {
    # Update with your Terraform Cloud organization name
    organization = "roboad"

    workspaces {
      name = "roboad-fast-ws"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

provider "vercel" {
  # API token set via VERCEL_API_TOKEN environment variable in Terraform Cloud
}
