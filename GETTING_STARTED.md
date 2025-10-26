# Getting Started - Choose Your Path

Welcome! Choose the best path for your setup:

## 🚀 Quick Start (30 minutes)
**Best for**: Getting up and running fast

Follow: **[QUICKSTART.md](QUICKSTART.md)**

```bash
# 1. Create IAM user
cd infra/bootstrap && terraform apply

# 2. Configure Terraform Cloud (via UI)
# 3. Deploy infrastructure
cd ../environments/shared && terraform apply
cd ../prod && terraform apply

# 4. Configure GitHub Secrets (via UI)
# 5. Test!
```

---

## 📚 Detailed Setup (1 hour)
**Best for**: Understanding every step

Follow: **[SETUP.md](SETUP.md)**

Includes:
- Detailed explanations
- Multiple options for each step
- Troubleshooting guidance
- Security best practices
- Cost optimization tips

---

## 🔄 Migrating Existing Infrastructure
**Best for**: If you already have Terraform deployed

Follow: **[MIGRATION.md](MIGRATION.md)**

Includes:
- Parallel deployment strategy
- Import existing resources
- Rollback procedures
- Testing checklist

---

## 🤖 Automation Options

### IAM User Creation

Choose one:

| Option | Time | Skill Level | Documentation |
|--------|------|-------------|---------------|
| **Terraform** | 2 min | Intermediate | [infra/bootstrap/README.md](infra/bootstrap/README.md) |
| **Bash Script** | 2 min | Beginner | [.github/AUTOMATION_GUIDE.md](.github/AUTOMATION_GUIDE.md) |
| **Manual (Console)** | 10 min | Beginner | [SETUP.md Step 1](SETUP.md#step-1-create-aws-iam-user-for-automation) |

**Recommended**: Use Terraform for production

```bash
cd infra/bootstrap
terraform init && terraform apply
```

---

## 📖 Complete Documentation Map

### Setup Guides
- **[QUICKSTART.md](QUICKSTART.md)** - 30-minute quick start
- **[SETUP.md](SETUP.md)** - Comprehensive setup guide
- **[MIGRATION.md](MIGRATION.md)** - Migration from old infrastructure

### Implementation Details
- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Full implementation overview
- **[infra/README.md](infra/README.md)** - Infrastructure documentation
- **[infra/bootstrap/README.md](infra/bootstrap/README.md)** - IAM user automation

### Automation
- **[.github/AUTOMATION_GUIDE.md](.github/AUTOMATION_GUIDE.md)** - Automation options explained
- **[.github/workflows/](..github/workflows/)** - GitHub Actions workflows

### Original Docs
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Original deployment guide (reference)

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                 SETUP PHASE (One Time)                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Create IAM User (Terraform/Script/Manual)               │
│     ├─ IAM Policy (scoped permissions)                      │
│     ├─ IAM User (github-terraform-deployer)                 │
│     └─ Access Keys                                          │
│                                                              │
│  2. Configure Terraform Cloud                               │
│     ├─ Workspace: roboad-fast-ws-shared                     │
│     ├─ Workspace: roboad-fast-ws-prod                       │
│     └─ Variables: AWS creds, API keys                       │
│                                                              │
│  3. Configure GitHub Secrets                                │
│     ├─ AWS_ACCESS_KEY_ID                                    │
│     ├─ AWS_SECRET_ACCESS_KEY                                │
│     └─ TF_API_TOKEN                                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│              INFRASTRUCTURE DEPLOYMENT                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Shared Resources (Deploy Once)                             │
│  ├─ VPC (10.0.0.0/16)                                       │
│  ├─ ECR Repository                                          │
│  ├─ IAM Roles (ECS execution/task)                          │
│  ├─ Secrets Manager (API keys)                              │
│  └─ CloudWatch Logs                                         │
│                                                              │
│  Production Environment                                     │
│  ├─ ALB (roboad-backend-prod-alb)                           │
│  ├─ ECS Cluster                                             │
│  ├─ ECS Service (2 tasks, auto-scale 1-10)                  │
│  └─ Security Groups                                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                     CI/CD FLOW                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Pull Request Flow:                                         │
│  PR Created → GitHub Actions                                │
│    ├─ Build Docker image (pr-123)                           │
│    ├─ Push to ECR                                           │
│    ├─ Create TF workspace (pr-123)                          │
│    ├─ Deploy infrastructure                                 │
│    └─ Comment URL on PR                                     │
│                                                              │
│  PR Closed → GitHub Actions                                 │
│    ├─ Destroy infrastructure                                │
│    ├─ Delete TF workspace                                   │
│    ├─ Delete ECR images                                     │
│    └─ Comment confirmation                                  │
│                                                              │
│  Production Flow:                                           │
│  Merge to main → GitHub Actions                             │
│    ├─ Build Docker image (latest + SHA)                     │
│    ├─ Push to ECR                                           │
│    ├─ Update ECS service                                    │
│    └─ Wait for stability                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## ✅ What You'll Get

### Infrastructure
- ✅ Production environment on AWS ECS Fargate
- ✅ Application Load Balancer with WebSocket support
- ✅ Auto-scaling (1-10 tasks based on CPU)
- ✅ VPC with public/private subnets
- ✅ ECR for Docker images
- ✅ Secrets Manager for API keys
- ✅ CloudWatch logging and monitoring

### CI/CD
- ✅ Automated PR environments (ephemeral)
- ✅ Automated production deployments
- ✅ Docker image building and pushing
- ✅ Infrastructure as Code with Terraform
- ✅ State management via Terraform Cloud

### Developer Experience
- ✅ PR comments with environment URLs
- ✅ Auto-cleanup of PR resources
- ✅ GitHub Actions workflows
- ✅ Comprehensive documentation

---

## 💰 Cost Estimate

| Component | Monthly Cost |
|-----------|--------------|
| Shared resources (NAT, ECR, Secrets) | ~$35 |
| Production (ECS + ALB) | ~$45 |
| Per active PR environment | ~$22 |
| **Total (no PRs)** | **~$80** |
| **Total (2 active PRs)** | **~$124** |

**Note**: PRs are auto-destroyed when closed, so you only pay while they're active.

---

## 🎯 Next Steps

### For Quick Start:
1. **[Run QUICKSTART.md](QUICKSTART.md)** - Get up and running in 30 minutes

### For Detailed Setup:
1. **[Read SETUP.md](SETUP.md)** - Comprehensive guide with explanations

### For Migration:
1. **[Read MIGRATION.md](MIGRATION.md)** - Migration strategy and steps

### For Understanding:
1. **[Read IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Full overview

---

## 🆘 Help & Support

### Documentation
- **Quick questions**: Check [QUICKSTART.md](QUICKSTART.md)
- **Detailed info**: See [SETUP.md](SETUP.md)
- **Troubleshooting**: Each guide has a troubleshooting section
- **IAM automation**: See [infra/bootstrap/README.md](infra/bootstrap/README.md)

### Common Issues

**Terraform Cloud credentials expired**
→ Solution: [SETUP.md Step 1](SETUP.md#step-1-create-aws-iam-user-for-automation)

**ECS tasks not starting**
→ Check CloudWatch logs: `aws logs tail /ecs/roboad-backend --follow`

**GitHub Actions failing**
→ Verify secrets in GitHub Settings → Secrets

**High costs**
→ Check for orphaned PR environments in Terraform Cloud

---

## 📝 Quick Reference

### Useful Commands

```bash
# View production logs
aws logs tail /ecs/roboad-backend --follow --region us-east-2

# Force new deployment
aws ecs update-service \
  --cluster roboad-backend-prod-cluster \
  --service roboad-backend-prod-service \
  --force-new-deployment

# View Terraform outputs
cd infra/environments/prod
terraform output

# Rotate IAM credentials
cd infra/bootstrap
terraform apply -replace=aws_iam_access_key.github_terraform_deployer
```

### Directory Structure

```
langgraph-stream/
├── GETTING_STARTED.md         ← You are here
├── QUICKSTART.md              ← 30-min quick start
├── SETUP.md                   ← Detailed setup
├── MIGRATION.md               ← Migration guide
├── IMPLEMENTATION_SUMMARY.md  ← Full overview
│
├── .github/
│   ├── workflows/             ← GitHub Actions
│   └── AUTOMATION_GUIDE.md    ← Automation options
│
└── infra/
    ├── bootstrap/             ← IAM user creation
    ├── modules/               ← Terraform modules
    └── environments/          ← Deployments
        ├── shared/            ← Deploy first
        ├── prod/              ← Deploy second
        └── pr-template/       ← Auto by GH Actions
```

---

**Ready to start? Pick a path above and let's go!** 🚀
