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
      version = "~> 5.80"
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
  llama_api_key_secret_arn  = data.terraform_remote_state.shared.outputs.llama_api_key_secret_arn
  steel_api_key_secret_arn  = data.terraform_remote_state.shared.outputs.steel_api_key_secret_arn
  serpapi_key_secret_arn    = data.terraform_remote_state.shared.outputs.serpapi_key_secret_arn

  # CloudWatch (from shared workspace)
  cloudwatch_log_group_name = data.terraform_remote_state.shared.outputs.cloudwatch_log_group_name

  # ALB
  alb_idle_timeout = var.alb_idle_timeout

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
