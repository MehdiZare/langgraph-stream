# Terraform Infrastructure Updates

This document outlines the infrastructure changes made to support Clerk authentication, Supabase database, and S3 storage integration.

## What Was Added

### 1. New Variables (variables.tf)

**Clerk Authentication**:
```hcl
variable "clerk_secret_key" { ... }
variable "clerk_publishable_key" { ... }
```

**Supabase Database**:
```hcl
variable "supabase_url" { ... }
variable "supabase_anon_key" { ... }
variable "supabase_service_role_key" { ... }
```

**AWS S3 Storage**:
```hcl
variable "s3_bucket_name" { ... }
variable "aws_access_key_id" { ... }
variable "aws_secret_access_key" { ... }
```

### 2. S3 Bucket for Scan Data (main.tf)

**Resources Created**:
- `aws_s3_bucket.scan_data` - Main S3 bucket
- `aws_s3_bucket_versioning.scan_data` - Versioning disabled
- `aws_s3_bucket_lifecycle_configuration.scan_data` - Expire scans after 90 days
- `aws_s3_bucket_public_access_block.scan_data` - Block all public access

**Bucket Structure**:
```
s3://{bucket_name}/
  └── scans/
      └── {scan_id}/
          ├── screenshot.png
          ├── page.html
          ├── raw_data.json
          └── metadata.json
```

### 3. AWS Secrets Manager

**New Secrets Added**:
- `clerk-secret-key` - Clerk authentication secret
- `supabase-service-role-key` - Supabase service role for backend
- `aws-access-key-id` - AWS credentials for S3
- `aws-secret-access-key` - AWS credentials for S3

### 4. IAM Policies

**Updated Policies**:
- `ecs_secrets_access` - Now includes access to all 7 secrets
- `ecs_s3_access` - New policy for S3 operations:
  - `s3:PutObject` - Upload files
  - `s3:GetObject` - Download files
  - `s3:DeleteObject` - Remove files
  - `s3:ListBucket` - List bucket contents

### 5. ECS Task Definition

**New Environment Variables**:
```json
{
  "CLERK_PUBLISHABLE_KEY": "pk_live_...",
  "SUPABASE_URL": "https://xxx.supabase.co",
  "SUPABASE_ANON_KEY": "eyJ...",
  "AWS_REGION": "us-east-2",
  "S3_BUCKET_NAME": "your-bucket-name"
}
```

**New Secrets (from Secrets Manager)**:
```json
{
  "CLERK_SECRET_KEY": "sk_live_...",
  "SUPABASE_SERVICE_ROLE_KEY": "eyJ...",
  "AWS_ACCESS_KEY_ID": "AKIA...",
  "AWS_SECRET_ACCESS_KEY": "..."
}
```

### 6. Vercel Integration

**New Environment Variable**:
- `NEXT_PUBLIC_BACKEND_URL` - Same as `NEXT_PUBLIC_WEBSOCKET_URL`
- Injected automatically to production, preview, and development environments

---

## Setup Instructions

### 1. Set Variables in Terraform Cloud

Navigate to your Terraform Cloud workspace and add the following variables:

#### Sensitive Variables (mark as sensitive):

```
clerk_secret_key = "sk_live_xxxxxxxxxxxxx"
supabase_service_role_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
aws_access_key_id = "AKIAIOSFODNN7EXAMPLE"
aws_secret_access_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

#### Regular Variables:

```
clerk_publishable_key = "pk_live_xxxxxxxxxxxxx"
supabase_url = "https://ckjqhvhqtiaiczqgggpo.supabase.co"
supabase_anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
s3_bucket_name = "roboad-scan-data-production"
```

### 2. Where to Find These Values

**Clerk**:
- Dashboard: https://dashboard.clerk.com
- Navigate to: API Keys section
- Copy: `CLERK_SECRET_KEY` and `CLERK_PUBLISHABLE_KEY`

**Supabase**:
- Dashboard: https://supabase.com/dashboard
- Navigate to: Settings → API
- Copy:
  - `Project URL` → `supabase_url`
  - `anon public` → `supabase_anon_key`
  - `service_role` (click reveal) → `supabase_service_role_key`

**AWS Credentials**:
- IAM Console: https://console.aws.amazon.com/iam
- Create new IAM user with S3 access or use existing credentials
- Copy: Access Key ID and Secret Access Key

**S3 Bucket Name**:
- Choose a globally unique name (e.g., `roboad-scan-data-production`)
- The bucket will be created automatically by Terraform

### 3. Apply Terraform Changes

```bash
cd infra

# Initialize Terraform (if not already done)
terraform init

# Review changes
terraform plan

# Apply changes
terraform apply
```

### 4. Verify Deployment

After applying, verify:

1. **S3 Bucket Created**:
   ```bash
   aws s3 ls | grep roboad-scan-data
   ```

2. **Secrets in Secrets Manager**:
   ```bash
   aws secretsmanager list-secrets | grep roboad-backend
   ```

3. **ECS Task Running**:
   ```bash
   aws ecs list-tasks --cluster roboad-backend-cluster
   ```

4. **Vercel Environment Variables**:
   - Check Vercel dashboard
   - Verify `NEXT_PUBLIC_BACKEND_URL` is set

---

## Infrastructure Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud                                │
│                                                                  │
│  ┌──────────────┐      ┌──────────────┐     ┌─────────────┐   │
│  │  S3 Bucket   │      │   Secrets    │     │   ECS Task  │   │
│  │  (Scan Data) │      │   Manager    │     │  (Backend)  │   │
│  │              │      │              │     │             │   │
│  │ scans/       │◄─────┤ Clerk Keys   │────►│ Port 8010   │   │
│  │  {id}/       │      │ Supabase     │     │             │   │
│  │   *.png      │      │ AWS Creds    │     └─────┬───────┘   │
│  └──────────────┘      └──────────────┘           │           │
│                                                    │           │
│                                         ┌──────────▼───────┐   │
│                                         │       ALB        │   │
│                                         │  (Load Balancer) │   │
│                                         └──────────┬───────┘   │
└────────────────────────────────────────────────────┼───────────┘
                                                     │
                                                     │ HTTP
                                                     │
                                          ┌──────────▼───────┐
                                          │ Vercel Frontend  │
                                          │  (Next.js)       │
                                          │  + Clerk Auth    │
                                          └──────────────────┘
```

---

## Security Notes

1. **Secrets Management**:
   - All sensitive keys stored in AWS Secrets Manager
   - ECS tasks pull secrets at runtime
   - Never commit secrets to git

2. **S3 Security**:
   - Public access completely blocked
   - Only ECS tasks can read/write
   - Presigned URLs for temporary access

3. **IAM Least Privilege**:
   - ECS task role limited to specific S3 bucket
   - Secrets access scoped to required secrets only

4. **Network Security**:
   - ECS tasks in private subnets
   - ALB in public subnets
   - No direct internet access to containers

---

## Cost Estimate

**New Resources**:
- S3 Storage: ~$0.023/GB/month + requests
- Secrets Manager: $0.40/secret/month × 4 = $1.60/month
- No additional compute costs (existing ECS)

**Estimated Monthly Cost**: ~$2-5/month (depending on scan volume)

---

## Troubleshooting

### Task fails to start
```bash
# Check task logs
aws logs tail /ecs/roboad-backend --follow

# Check task definition
aws ecs describe-task-definition --task-definition roboad-backend
```

### S3 permission errors
```bash
# Verify IAM policy
aws iam get-role-policy \
  --role-name roboad-backend-ecs-task-role \
  --policy-name roboad-backend-ecs-s3-access
```

### Secrets not loading
```bash
# Verify secrets exist
aws secretsmanager list-secrets | grep roboad

# Test secret retrieval
aws secretsmanager get-secret-value \
  --secret-id roboad-backend/clerk-secret-key
```

---

## Rollback Plan

If issues occur:

```bash
# Rollback to previous version
cd infra
terraform apply -target=aws_ecs_task_definition.app \
  -var="app_image_tag=previous-tag"

# Or destroy only new resources
terraform destroy -target=aws_s3_bucket.scan_data
terraform destroy -target=aws_secretsmanager_secret.clerk_secret_key
```

---

## Next Steps

1. ✅ Apply Terraform changes
2. ✅ Apply Supabase migration: `supabase db push`
3. ✅ Deploy new Docker image with updated dependencies
4. ✅ Test authentication flow
5. ✅ Verify S3 uploads working
6. ✅ Share API docs with frontend team

---

## Questions?

See:
- `docs/AUTH_STRATEGY.md` - Authentication details
- `docs/API_DOCUMENTATION.md` - API reference for frontend
- `claude.md` - Project guidelines
