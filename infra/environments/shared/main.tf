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
# CLOUDFLARE DATA SOURCES
# ============================================================================

data "cloudflare_zones" "main" {
  filter {
    name = "roboad.ai"
  }
}

# ============================================================================
# ACM WILDCARD CERTIFICATE
# ============================================================================

resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.roboad.ai"
  validation_method = "DNS"

  subject_alternative_names = [
    "roboad.ai"  # Include apex domain
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-wildcard-cert"
    Environment = "shared"
    ManagedBy   = "Terraform"
  }
}

# Cloudflare DNS validation records
resource "cloudflare_dns_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.cloudflare_zones.main.zones[0].id
  name    = each.value.name
  value   = trimsuffix(each.value.record, ".")
  type    = each.value.type
  ttl     = 60
  proxied = false

  comment = "ACM certificate validation for ${each.key}"
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for record in cloudflare_dns_record.cert_validation : record.hostname]
}

# ============================================================================
# SERVICE-LINKED ROLE FOR ECS AUTO SCALING
# ============================================================================

# Note: The service-linked role for ECS Application Auto Scaling already exists.
# It was created during the initial deployment and does not need to be managed by Terraform.
# The IAM policy update we made allows the automation user to create it if needed in future deployments.
