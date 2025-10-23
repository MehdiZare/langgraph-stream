# ============================================================================
# SHARED RESOURCES MODULE
# Creates ECR, IAM roles, Secrets Manager, and CloudWatch log groups
# ============================================================================

# ============================================================================
# ECR REPOSITORY
# ============================================================================

resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-ecr"
    }
  )
}

# ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 30 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-ecs-task-execution-role"
    }
  )
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Policy for accessing Secrets Manager
resource "aws_iam_role_policy" "ecs_secrets_access" {
  name = "${var.project_name}-ecs-secrets-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.llama_api_key.arn,
          aws_secretsmanager_secret.steel_api_key.arn,
          aws_secretsmanager_secret.serpapi_key.arn
        ]
      }
    ]
  })
}

# ECS Task Role (for application runtime)
resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-ecs-task-role"
    }
  )
}

# Policy for S3 access from ECS tasks
resource "aws_iam_role_policy" "ecs_s3_access" {
  name = "${var.project_name}-ecs-s3-access"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.scans.arn,
          "${aws_s3_bucket.scans.arn}/*"
        ]
      }
    ]
  })
}

# ============================================================================
# SECRETS MANAGER
# ============================================================================

resource "aws_secretsmanager_secret" "llama_api_key" {
  name        = "${var.project_name}/llama-api-key"
  description = "Llama API key for ${var.project_name}"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-llama-api-key"
    }
  )
}

resource "aws_secretsmanager_secret_version" "llama_api_key" {
  secret_id     = aws_secretsmanager_secret.llama_api_key.id
  secret_string = var.llama_api_key
}

resource "aws_secretsmanager_secret" "steel_api_key" {
  name        = "${var.project_name}/steel-api-key"
  description = "Steel.dev API key for ${var.project_name}"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-steel-api-key"
    }
  )
}

resource "aws_secretsmanager_secret_version" "steel_api_key" {
  secret_id     = aws_secretsmanager_secret.steel_api_key.id
  secret_string = var.steel_api_key
}

resource "aws_secretsmanager_secret" "serpapi_key" {
  name        = "${var.project_name}/serpapi-key"
  description = "SerpAPI key for ${var.project_name}"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-serpapi-key"
    }
  )
}

resource "aws_secretsmanager_secret_version" "serpapi_key" {
  secret_id     = aws_secretsmanager_secret.serpapi_key.id
  secret_string = var.serpapi_key
}

# ============================================================================
# CLOUDWATCH LOGS
# ============================================================================

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-logs"
    }
  )
}

# ============================================================================
# S3 BUCKET FOR SCAN DATA
# ============================================================================

resource "aws_s3_bucket" "scans" {
  bucket = "${var.project_name}-scans"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-scans"
    }
  )
}

# Enable encryption by default
resource "aws_s3_bucket_server_side_encryption_configuration" "scans" {
  bucket = aws_s3_bucket.scans.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "scans" {
  bucket = aws_s3_bucket.scans.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
