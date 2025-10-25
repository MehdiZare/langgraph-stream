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
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
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

provider "cloudflare" {
  # API token set via CLOUDFLARE_API_TOKEN environment variable in Terraform Cloud
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

  clerk_secret_key          = var.clerk_secret_key
  clerk_publishable_key     = var.clerk_publishable_key
  supabase_url              = var.supabase_url
  supabase_anon_key         = var.supabase_anon_key
  supabase_service_role_key = var.supabase_service_role_key

  log_retention_days = var.log_retention_days

  tags = {
    Environment = "shared"
  }
}

# ============================================================================
# CLOUDFLARE CONFIGURATION
# ============================================================================

# Hardcoded zone ID for roboad.ai
# Note: Cloudflare provider v5 has broken zone lookup by name
# See: https://github.com/cloudflare/terraform-provider-cloudflare/issues/4958
locals {
  cloudflare_zone_id = "37a732a3f8084c6331df47901dbc2cc5"
}

# ============================================================================
# SSL/TLS CONFIGURATION
# ============================================================================
# Using Cloudflare Enterprise SSL instead of ACM
# - Cloudflare provides SSL termination (user → Cloudflare)
# - Backend ALB uses HTTP only (Cloudflare → ALB)
# - Configured in Cloudflare Dashboard: SSL/TLS → Flexible mode
# - No ACM certificate needed
# ============================================================================

# ============================================================================
# SERVICE-LINKED ROLE FOR ECS AUTO SCALING
# ============================================================================

# Note: The service-linked role for ECS Application Auto Scaling already exists.
# It was created during the initial deployment and does not need to be managed by Terraform.
# The IAM policy update we made allows the automation user to create it if needed in future deployments.
