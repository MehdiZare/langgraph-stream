# ============================================================================
# SHARED ENVIRONMENT
# Creates networking and shared resources (VPC, ECR, IAM, Secrets)
# This should be deployed once and shared across all environments
# ============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  cloud {
    organization = "roboad"

    workspaces {
      name = "roboad-fast-ws-shared"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "shared"
      ManagedBy   = "Terraform"
    }
  }
}

# ============================================================================
# NETWORKING MODULE
# ============================================================================

module "networking" {
  source = "../../modules/networking"

  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones

  tags = {
    Environment = "shared"
  }
}

# ============================================================================
# SHARED RESOURCES MODULE
# ============================================================================

module "shared" {
  source = "../../modules/shared"

  project_name = var.project_name

  llama_api_key = var.llama_api_key
  steel_api_key = var.steel_api_key
  serpapi_key   = var.serpapi_key

  log_retention_days = var.log_retention_days

  tags = {
    Environment = "shared"
  }
}

# ============================================================================
# SERVICE-LINKED ROLE FOR ECS AUTO SCALING
# ============================================================================

# Note: The service-linked role for ECS Application Auto Scaling already exists.
# It was created during the initial deployment and does not need to be managed by Terraform.
# The IAM policy update we made allows the automation user to create it if needed in future deployments.
