# Quick Start Guide

Get your infrastructure deployed in under 30 minutes.

## Prerequisites

- AWS account with admin access
- Terraform Cloud account (free)
- GitHub repository
- API keys (Llama, Steel.dev, SerpAPI)

## Step 1: Create IAM User (5 minutes)

**Option A: Terraform (Recommended)**

```bash
cd infra/bootstrap
terraform init
terraform apply

# Save these credentials!
terraform output access_key_id
terraform output secret_access_key
```

**Option B: AWS CLI Script**

```bash
cd infra/bootstrap
./create-iam-user.sh
```

**Option C: Manual** - See SETUP.md Step 1

## Step 2: Configure Terraform Cloud (5 minutes)

1. Create account at [app.terraform.io](https://app.terraform.io)
2. Create organization: `roboad`
3. Create workspaces:
   - `roboad-fast-ws-shared`
   - `roboad-fast-ws-prod`

For each workspace, add variables:

**Environment Variables** (sensitive):
- `AWS_ACCESS_KEY_ID` = (from Step 1)
- `AWS_SECRET_ACCESS_KEY` = (from Step 1)

**Terraform Variables** (sensitive, shared workspace only):
- `llama_api_key` = your Llama key
- `steel_api_key` = your Steel key
- `serpapi_key` = your SerpAPI key

**Terraform Variables** (prod workspace only):
- `vercel_project_id` = your Vercel project ID (optional)

## Step 3: Deploy Shared Resources (10 minutes)

```bash
cd infra/environments/shared
terraform init
terraform apply

# Note the outputs
terraform output
```

## Step 4: Build & Push Docker Image (5 minutes)

```bash
# Login to ECR
aws ecr get-login-password --region us-east-2 | \
  docker login --username AWS --password-stdin \
  $(cd infra/environments/shared && terraform output -raw ecr_repository_url | cut -d'/' -f1)

# Build and push from project root
cd ../..
docker build -t roboad-backend:latest .
docker tag roboad-backend:latest \
  $(cd infra/environments/shared && terraform output -raw ecr_repository_url):latest
docker push \
  $(cd infra/environments/shared && terraform output -raw ecr_repository_url):latest
```

## Step 5: Deploy Production (5 minutes)

```bash
cd infra/environments/prod
terraform init
terraform apply

# Get your production URL
terraform output alb_url
```

## Step 6: Configure GitHub (2 minutes)

Go to GitHub repo → Settings → Secrets and variables → Actions

Add these secrets:

| Secret | Value |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | From Step 1 |
| `AWS_SECRET_ACCESS_KEY` | From Step 1 |
| `TF_API_TOKEN` | From Terraform Cloud user settings |
| `LLAMA_API_KEY` | Your Llama key |
| `STEEL_API_KEY` | Your Steel key |
| `SERPAPI_KEY` | Your SerpAPI key |
| `VERCEL_API_TOKEN` | Your Vercel token (optional) |

## Step 7: Test (5 minutes)

**Test Production:**
```bash
curl $(cd infra/environments/prod && terraform output -raw alb_url)/health
```

**Test PR Environment:**
```bash
# Create a test branch and PR
git checkout -b test/pr-deployment
git commit --allow-empty -m "Test PR deployment"
git push origin test/pr-deployment

# Create PR on GitHub
# GitHub Actions will comment with environment URL
# Test the URL
# Close PR to trigger cleanup
```

## What You Get

✅ **Production Environment**
- ECS service running on Fargate
- Application Load Balancer
- Auto-scaling (1-10 tasks)
- CloudWatch logging

✅ **PR Environments**
- Ephemeral environment per PR
- Auto-created on PR open
- Auto-destroyed on PR close
- Smaller resources (cost optimized)

✅ **CI/CD Pipeline**
- Auto-deploy to prod on merge to main
- Auto-build and push Docker images
- GitHub Actions workflows configured

## Cost Estimate

- **Shared**: ~$35/month (NAT, ECR, Secrets)
- **Production**: ~$45/month (ECS, ALB)
- **Per PR**: ~$22/month (auto-cleaned up)

**Total**: ~$80-100/month + active PRs

## Architecture

```
GitHub PR → GitHub Actions → ECR + Terraform Cloud → AWS ECS
             ├─ Build image
             ├─ Push to ECR
             ├─ Create workspace
             └─ Deploy infrastructure

PR Closed → GitHub Actions → Terraform Cloud → Destroy Resources
            ├─ Destroy ECS
            ├─ Destroy ALB
            ├─ Delete workspace
            └─ Clean ECR images

Merge to Main → GitHub Actions → ECR → Update Production
                ├─ Build image
                ├─ Push to ECR
                └─ Update ECS service
```

## Troubleshooting

### Terraform Error: "ExpiredToken"
→ Use long-term IAM credentials (Step 1), not temporary/SSO

### ECS Tasks Not Starting
```bash
# Check logs
aws logs tail /ecs/roboad-backend --follow --region us-east-2
```

### GitHub Actions Failing
→ Check secrets are set correctly in GitHub

### Need Help?
- Detailed guide: `SETUP.md`
- Migration guide: `MIGRATION.md`
- Full summary: `IMPLEMENTATION_SUMMARY.md`
- Bootstrap docs: `infra/bootstrap/README.md`

## Next Steps

1. **Add HTTPS**: Configure ACM certificate
2. **Custom Domain**: Use Route 53 or Cloudflare
3. **Monitoring**: Set up CloudWatch alarms
4. **Optimize**: Review and adjust resource sizing

## Quick Commands

```bash
# View production logs
aws logs tail /ecs/roboad-backend --follow --region us-east-2

# Force new deployment
aws ecs update-service \
  --cluster roboad-backend-prod-cluster \
  --service roboad-backend-prod-service \
  --force-new-deployment \
  --region us-east-2

# View ECS service status
aws ecs describe-services \
  --cluster roboad-backend-prod-cluster \
  --services roboad-backend-prod-service \
  --region us-east-2

# List all PR workspaces
# Go to Terraform Cloud → search "roboad-fast-ws-pr-"
```

## File Structure

```
langgraph-stream/
├── .github/workflows/          # GitHub Actions
│   ├── pr-deploy.yml          # Deploy PR env
│   ├── pr-cleanup.yml         # Cleanup PR env
│   └── prod-deploy.yml        # Deploy to prod
├── infra/
│   ├── bootstrap/             # IAM user creation
│   │   ├── iam-user.tf       # Terraform config
│   │   ├── create-iam-user.sh # Bash script
│   │   └── README.md
│   ├── modules/               # Reusable modules
│   │   ├── networking/
│   │   ├── shared/
│   │   └── ecs-service/
│   └── environments/          # Deployments
│       ├── shared/            # Deploy first
│       ├── prod/              # Deploy second
│       └── pr-template/       # Auto by GH Actions
├── QUICKSTART.md              # This file
├── SETUP.md                   # Detailed guide
├── MIGRATION.md               # Migration guide
└── IMPLEMENTATION_SUMMARY.md  # Full overview
```

---

**Ready?** Start with Step 1! 🚀
