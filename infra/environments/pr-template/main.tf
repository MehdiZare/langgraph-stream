# ============================================================================
# PR ENVIRONMENT TEMPLATE
# Creates ephemeral ECS service for PR testing
# Depends on shared environment resources
# Note: GitHub Actions will use this as a template and override variables
# ============================================================================

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
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }

  # Workspace is set via TF_WORKSPACE environment variable by GitHub Actions
  # This allows dynamic workspace creation per PR
  cloud {
    organization = "roboad"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "pr-${var.pr_number}"
      ManagedBy   = "Terraform"
      PRNumber    = var.pr_number
      # Auto-cleanup tag for cost optimization
      AutoCleanup = "true"
    }
  }
}

provider "vercel" {
  # API token set via VERCEL_API_TOKEN environment variable in Terraform Cloud
}

provider "cloudflare" {
  # API token set via CLOUDFLARE_API_TOKEN environment variable in Terraform Cloud
}

# ============================================================================
# DATA SOURCES - Fetch shared resources from shared workspace
# ============================================================================

data "terraform_remote_state" "shared" {
  backend = "remote"

  config = {
    organization = "roboad"
    workspaces = {
      name = "roboad-fast-ws-shared"
    }
  }
}

# ============================================================================
# CLOUDFLARE DNS RECORD - api-pr-{number}.roboad.ai → PR ALB
# ============================================================================

resource "cloudflare_dns_record" "api_pr" {
  zone_id = data.terraform_remote_state.shared.outputs.cloudflare_zone_id
  name    = "api-pr-${var.pr_number}"
  content = module.ecs_service.alb_dns_name
  type    = "CNAME"
  ttl     = 1  # Automatic TTL when proxied
  proxied = true  # Enable Cloudflare proxy for SSL termination and Enterprise features

  comment = "PR #${var.pr_number} environment - managed by Terraform"
}

# ============================================================================
# ECS SERVICE MODULE - PR Environment
# ============================================================================

module "ecs_service" {
  source = "../../modules/ecs-service"

  service_name = "${var.project_name}-pr-${var.pr_number}"
  environment  = "pr-${var.pr_number}"
  aws_region   = var.aws_region

  # Networking (from shared workspace)
  vpc_id             = data.terraform_remote_state.shared.outputs.vpc_id
  public_subnet_ids  = data.terraform_remote_state.shared.outputs.public_subnet_ids
  private_subnet_ids = data.terraform_remote_state.shared.outputs.private_subnet_ids

  # Container - Use PR-specific image tag
  container_image = "${data.terraform_remote_state.shared.outputs.ecr_repository_url}:pr-${var.pr_number}"
  container_port  = var.container_port

  # ECS Task - Smaller resources for PR environments
  task_cpu       = var.ecs_task_cpu
  task_memory    = var.ecs_task_memory
  desired_count  = var.ecs_desired_count

  # IAM Roles (from shared workspace)
  task_execution_role_arn = data.terraform_remote_state.shared.outputs.ecs_task_execution_role_arn
  task_role_arn           = data.terraform_remote_state.shared.outputs.ecs_task_role_arn

  # Secrets (from shared workspace)
  llama_api_key_secret_arn              = data.terraform_remote_state.shared.outputs.llama_api_key_secret_arn
  steel_api_key_secret_arn              = data.terraform_remote_state.shared.outputs.steel_api_key_secret_arn
  serpapi_key_secret_arn                = data.terraform_remote_state.shared.outputs.serpapi_key_secret_arn
  clerk_secret_key_arn                  = data.terraform_remote_state.shared.outputs.clerk_secret_key_arn
  clerk_publishable_key_arn             = data.terraform_remote_state.shared.outputs.clerk_publishable_key_arn
  supabase_url_secret_arn               = data.terraform_remote_state.shared.outputs.supabase_url_secret_arn
  supabase_anon_key_secret_arn          = data.terraform_remote_state.shared.outputs.supabase_anon_key_secret_arn
  supabase_service_role_key_secret_arn  = data.terraform_remote_state.shared.outputs.supabase_service_role_key_secret_arn

  # S3 Storage (from shared workspace)
  s3_bucket_name = data.terraform_remote_state.shared.outputs.s3_scans_bucket_name

  # CloudWatch (from shared workspace)
  cloudwatch_log_group_name = data.terraform_remote_state.shared.outputs.cloudwatch_log_group_name

  # ALB - Using Cloudflare SSL, no ACM certificate needed
  alb_idle_timeout = var.alb_idle_timeout
  certificate_arn  = ""  # Empty - using Cloudflare SSL termination
  domain_name      = "api-pr-${var.pr_number}.roboad.ai"

  # Auto Scaling - Disabled for PR environments
  enable_autoscaling = false

  # Monitoring - Disabled for cost savings
  enable_container_insights = false

  additional_environment_variables = [
    {
      name  = "PR_NUMBER"
      value = var.pr_number
    }
  ]

  tags = {
    Environment = "pr-${var.pr_number}"
    PRNumber    = var.pr_number
    AutoCleanup = "true"
  }
}

# ============================================================================
# VERCEL INTEGRATION - DISABLED
# ============================================================================
# Backend and frontend are in separate repositories with independent PR cycles.
# - Backend repo: This repository (langgraph-stream)
# - Frontend repo: Separate Vercel-connected repository
#
# Since Vercel is connected to the frontend repo, it cannot see backend branches
# (e.g., 'add-supabase'). Therefore, Vercel environment variables should be
# managed separately:
#
# Option 1 (Recommended): Set in Vercel Dashboard once
#   - NEXT_PUBLIC_BACKEND_URL = https://prod.api.roboad.ai
#   - All frontend previews connect to production backend
#
# Option 2: Manage per frontend PR manually in Vercel
#   - Set NEXT_PUBLIC_BACKEND_URL for specific frontend PR branches
#   - Point to corresponding backend PR environment if needed
#
# This keeps backend and frontend infrastructure cleanly separated.
# ============================================================================

# Vercel integration commented out - manage Vercel env vars separately

# resource "vercel_project_environment_variable" "backend_url" {
#   count = var.vercel_project_id != "" && var.git_branch != "" ? 1 : 0
#   project_id = var.vercel_project_id
#   team_id    = var.vercel_team_id
#   key        = "NEXT_PUBLIC_BACKEND_URL"
#   value      = module.ecs_service.service_url
#   target     = ["preview"]
# }

# resource "vercel_project_environment_variable" "pr_number_env" {
#   count = var.vercel_project_id != "" && var.git_branch != "" ? 1 : 0
#   project_id = var.vercel_project_id
#   team_id    = var.vercel_team_id
#   key        = "NEXT_PUBLIC_PR_NUMBER"
#   value      = var.pr_number
#   target     = ["preview"]
# }

# resource "vercel_deployment" "pr_preview" {
#   count = var.vercel_project_id != "" && var.git_branch != "" ? 1 : 0
#   project_id = var.vercel_project_id
#   team_id    = var.vercel_team_id
#   ref = var.git_branch
#   production = false

#   depends_on = [
#     vercel_project_environment_variable.backend_url,
#     vercel_project_environment_variable.pr_number_env
#   ]
# }
