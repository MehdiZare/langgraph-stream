# ============================================================================
# IAM USER FOR GITHUB ACTIONS & TERRAFORM CLOUD
# Run this ONCE to create the automation user
# ============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  # Use local state for bootstrap (or configure your own backend)
  backend "local" {
    path = "terraform-bootstrap.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================================================
# IAM POLICY - Permissions for Terraform to manage infrastructure
# ============================================================================

resource "aws_iam_policy" "terraform_deployer" {
  name        = "${var.project_name}-terraform-deployer-policy"
  description = "Policy for Terraform Cloud and GitHub Actions to deploy infrastructure"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageEC2"
        Effect = "Allow"
        Action = [
          "ec2:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageECS"
        Effect = "Allow"
        Action = [
          "ecs:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageECR"
        Effect = "Allow"
        Action = [
          "ecr:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageLoadBalancing"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageLogs"
        Effect = "Allow"
        Action = [
          "logs:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageAutoScaling"
        Effect = "Allow"
        Action = [
          "application-autoscaling:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageS3"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetBucketAcl",
          "s3:PutBucketAcl",
          "s3:GetBucketCORS",
          "s3:PutBucketCORS",
          "s3:DeleteBucketCORS",
          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:DeleteLifecycleConfiguration",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "s3:GetBucketWebsite",
          "s3:PutBucketWebsite",
          "s3:DeleteBucketWebsite",
          "s3:GetBucketLogging",
          "s3:PutBucketLogging",
          "s3:GetBucketRequestPayment",
          "s3:PutBucketRequestPayment",
          "s3:GetBucketNotification",
          "s3:PutBucketNotification",
          "s3:GetReplicationConfiguration",
          "s3:PutReplicationConfiguration",
          "s3:GetAccelerateConfiguration",
          "s3:PutAccelerateConfiguration",
          "s3:GetBucketObjectLockConfiguration",
          "s3:PutBucketObjectLockConfiguration",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-*",
          "arn:aws:s3:::${var.project_name}-*/*"
        ]
      },
      {
        Sid    = "ManageIAMRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:PassRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy"
        ]
        Resource = [
          "arn:aws:iam::*:role/${var.project_name}-*"
        ]
      },
      {
        Sid    = "ReadIAMPolicies"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions"
        ]
        Resource = "*"
      },
      {
        Sid    = "CreateServiceLinkedRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "arn:aws:iam::*:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "ecs.application-autoscaling.amazonaws.com"
          }
        }
      },
      {
        Sid    = "ManageACM"
        Effect = "Allow"
        Action = [
          "acm:RequestCertificate",
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "acm:DeleteCertificate",
          "acm:AddTagsToCertificate",
          "acm:RemoveTagsFromCertificate",
          "acm:GetCertificate",
          "acm:ListTagsForCertificate"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name      = "${var.project_name}-terraform-deployer-policy"
    ManagedBy = "Terraform Bootstrap"
  }
}

# ============================================================================
# IAM USER - For GitHub Actions and Terraform Cloud
# ============================================================================

resource "aws_iam_user" "github_terraform_deployer" {
  name = var.iam_user_name
  path = "/automation/"

  tags = {
    Name        = var.iam_user_name
    Purpose     = "GitHub Actions and Terraform Cloud automation"
    ManagedBy   = "Terraform Bootstrap"
    Environment = "all"
  }
}

# Attach the custom policy
resource "aws_iam_user_policy_attachment" "terraform_deployer" {
  user       = aws_iam_user.github_terraform_deployer.name
  policy_arn = aws_iam_policy.terraform_deployer.arn
}

# ============================================================================
# ACCESS KEY - Programmatic access
# ============================================================================

resource "aws_iam_access_key" "github_terraform_deployer" {
  user = aws_iam_user.github_terraform_deployer.name
}

# ============================================================================
# OUTPUTS - Save these securely!
# ============================================================================

output "iam_user_name" {
  description = "IAM user name"
  value       = aws_iam_user.github_terraform_deployer.name
}

output "iam_user_arn" {
  description = "IAM user ARN"
  value       = aws_iam_user.github_terraform_deployer.arn
}

output "access_key_id" {
  description = "AWS Access Key ID (save this securely!)"
  value       = aws_iam_access_key.github_terraform_deployer.id
  sensitive   = true
}

output "secret_access_key" {
  description = "AWS Secret Access Key (save this securely!)"
  value       = aws_iam_access_key.github_terraform_deployer.secret
  sensitive   = true
}

output "instructions" {
  description = "Next steps"
  value       = <<-EOT

  ====================================================================
  IAM USER CREATED SUCCESSFULLY
  ====================================================================

  User Name: ${aws_iam_user.github_terraform_deployer.name}
  User ARN:  ${aws_iam_user.github_terraform_deployer.arn}

  IMPORTANT: Save these credentials securely!

  To view the credentials:
    terraform output access_key_id
    terraform output secret_access_key

  Next Steps:

  1. Add to Terraform Cloud workspaces:
     - Variable: AWS_ACCESS_KEY_ID (environment, sensitive)
       Value: <run: terraform output -raw access_key_id>

     - Variable: AWS_SECRET_ACCESS_KEY (environment, sensitive)
       Value: <run: terraform output -raw secret_access_key>

  2. Add to GitHub Secrets:
     - Secret: AWS_ACCESS_KEY_ID
       Value: <run: terraform output -raw access_key_id>

     - Secret: AWS_SECRET_ACCESS_KEY
       Value: <run: terraform output -raw secret_access_key>

  3. Store in password manager or secrets vault

  ====================================================================
  EOT
}
