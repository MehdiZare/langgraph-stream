# ============================================================================
# PRODUCTION ENVIRONMENT
# Creates production ECS service with ALB
# Depends on shared environment resources
# ============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    vercel = {
      source  = "vercel/vercel"
      version = "~> 2.0"
    }
  }

  cloud {
    organization = "roboad"

    workspaces {
      name = "roboad-fast-ws-prod"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "production"
      ManagedBy   = "Terraform"
    }
  }
}

provider "vercel" {
  # API token set via VERCEL_API_TOKEN environment variable in Terraform Cloud
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
# ECS SERVICE MODULE - Production
# ============================================================================

module "ecs_service" {
  source = "../../modules/ecs-service"

  service_name = "${var.project_name}-prod"
  environment  = "production"
  aws_region   = var.aws_region

  # Networking (from shared workspace)
  vpc_id             = data.terraform_remote_state.shared.outputs.vpc_id
  public_subnet_ids  = data.terraform_remote_state.shared.outputs.public_subnet_ids
  private_subnet_ids = data.terraform_remote_state.shared.outputs.private_subnet_ids

  # Container
  container_image = "${data.terraform_remote_state.shared.outputs.ecr_repository_url}:${var.app_image_tag}"
  container_port  = var.container_port

  # ECS Task
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

  # ALB
  alb_idle_timeout = var.alb_idle_timeout

  # Auto Scaling
  enable_autoscaling        = true
  autoscaling_min_capacity  = var.ecs_min_capacity
  autoscaling_max_capacity  = var.ecs_max_capacity
  autoscaling_cpu_target    = var.ecs_cpu_target

  # Monitoring
  enable_container_insights = var.enable_container_insights

  tags = {
    Environment = "production"
  }
}

# ============================================================================
# VERCEL INTEGRATION
# ============================================================================

resource "vercel_project_environment_variable" "backend_url" {
  count = var.vercel_project_id != "" ? 1 : 0

  project_id = var.vercel_project_id
  team_id    = var.vercel_team_id
  key        = "NEXT_PUBLIC_BACKEND_URL"
  value      = "http://${module.ecs_service.alb_dns_name}"
  target     = ["production"]
}
