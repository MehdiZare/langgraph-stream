# LangGraph WebSocket Infrastructure (Terraform Cloud)

This directory contains Terraform configuration to deploy the LangGraph WebSocket application on AWS using ECS Fargate, with state management via Terraform Cloud.

## Architecture

```
┌─────────────────────┐
│  Vercel Frontend    │ ← NEXT_PUBLIC_WEBSOCKET_URL auto-configured
│  (Next.js)          │   via Terraform
└──────────┬──────────┘
           │
           │ WebSocket
           │
┌──────────▼──────────────────────────┐
│ Application Load Balancer (ALB)     │
│ - HTTP/HTTPS (80/443)                │
│ - WebSocket support (300s timeout)  │
└──────┬──────────────────────────────┘
       │
┌──────▼──────────────────────────────┐
│ ECS Fargate Service                  │
│ - 1-4 tasks (auto-scaling)           │
│ - 512 CPU / 1024 MB memory           │
│ - Private subnets                    │
└──────┬──────────────────────────────┘
       │
┌──────▼──────────────────────────────┐
│ External APIs                        │
│ - Steel.dev (screenshots)            │
│ - SerpAPI (Google/Bing search)       │
│ - Llama API (LLM analysis)           │
└──────────────────────────────────────┘
```

## Infrastructure Components

### Networking
- **VPC**: 10.0.0.0/16
- **Subnets**: 2 public + 2 private across 2 AZs
- **NAT Gateway**: Single NAT for cost optimization
- **Internet Gateway**: For public subnet internet access

### Compute
- **ECS Cluster**: Fargate launch type
- **ECS Service**: 1 task (scalable to 4)
- **Task Definition**: 512 CPU / 1024 MB RAM

### Load Balancing
- **ALB**: Internet-facing, HTTP listener
- **Target Group**: Health checks on /health endpoint
- **Sticky Sessions**: Enabled for WebSocket support

### Container Registry
- **ECR**: Private Docker registry
- **Lifecycle Policy**: Keep last 10 images

### Secrets
- **AWS Secrets Manager**: API keys stored securely
  - Llama API Key
  - Steel.dev API Key
  - SerpAPI Key

### Monitoring
- **CloudWatch Logs**: Container logs retention (7 days)
- **Auto Scaling**: CPU-based (target 70%)

### Vercel Integration
- **Automatic Environment Variable**: ALB URL pushed to Vercel
- **Variable Name**: NEXT_PUBLIC_WEBSOCKET_URL
- **Environments**: Production, Preview, Development
- **Frontend Access**: Next.js frontend automatically connects to WebSocket API

### State Management
- **Terraform Cloud**: Remote state storage and execution
  - Automatic state locking
  - State versioning and rollback
  - Team collaboration
  - Secure credential management

## Prerequisites

1. **Terraform Cloud Account**
   - Sign up at https://app.terraform.io/signup/account
   - Create or join an organization
   - Free tier: Up to 500 resources

2. **Vercel Account**
   - Sign up at https://vercel.com
   - Create or have access to a Next.js project
   - Obtain API token and project ID (see Quick Start step 5)

3. **Terraform** >= 1.5.0 installed
   ```bash
   brew install terraform  # macOS
   # or download from https://www.terraform.io/downloads
   ```

4. **AWS CLI** installed and configured (for local testing)
   ```bash
   aws configure
   ```

5. **Docker** installed (for building images)

6. **API Keys** (required for application to function):
   - Llama API key (for LLM analysis)
   - Steel.dev API key (for screenshots)
   - SerpAPI key (for Google/Bing search)

   These will be set as sensitive Terraform variables in step 4.

## Authentication: Static Credentials (Simplest)

This guide uses **static AWS credentials** for simplicity. For production deployments with enhanced security, see the [OIDC setup in Advanced Configuration](#oidc-with-aws-no-static-credentials).

## Quick Start

### 1. Login to Terraform Cloud

```bash
cd infra
terraform login
```

This will open a browser window to authenticate. After successful login, a token will be stored locally.

### 2. Update Organization Name

Edit `backend.tf` and replace `YOUR_ORGANIZATION_NAME` with your Terraform Cloud organization name:

```hcl
cloud {
  organization = "your-actual-org-name"  # ← Update this

  workspaces {
    name = "langgraph-websocket"
  }
}
```

### 3. Initialize Terraform

```bash
terraform init
```

This will:
- Connect to Terraform Cloud
- Create the workspace `langgraph-websocket` automatically
- Configure remote execution

### 4. Configure Credentials in Terraform Cloud

Go to your workspace:
`https://app.terraform.io/app/YOUR_ORG/workspaces/YOUR_WORKSPACE/variables`

#### Add Environment Variables (mark as sensitive):

| Variable Name | Value | Description |
|---------------|-------|-------------|
| `AWS_ACCESS_KEY_ID` | your-aws-access-key | AWS credentials |
| `AWS_SECRET_ACCESS_KEY` | your-aws-secret-key | AWS credentials |
| `VERCEL_API_TOKEN` | your-vercel-token | Get from [vercel.com/account/tokens](https://vercel.com/account/tokens) |

#### Add Terraform Variables (mark as sensitive):

| Variable Name | Value | Description |
|---------------|-------|-------------|
| `llama_api_key` | your-llama-key | LLM API key |
| `steel_api_key` | your-steel-key | Screenshot service API key |
| `serpapi_key` | your-serpapi-key | Search API key |
| `vercel_project_id` | prj_xxxxx | From Vercel Project Settings → General |
| `vercel_team_id` | team_xxxxx or `null` | Only if using Vercel teams |

**Important**:
- **Environment variables** = AWS and Vercel auth
- **Terraform variables** = Application API keys and config
- API keys will be injected into AWS Secrets Manager during deployment

**For enhanced security (production):** See [OIDC setup in Advanced Configuration](#oidc-with-aws-no-static-credentials) to avoid storing AWS credentials.

**What Terraform will do automatically:**
When you run `terraform apply`, it will:
- Create/update `NEXT_PUBLIC_WEBSOCKET_URL` in your Vercel project
- Set it to your ALB URL
- Apply to all Vercel environments (production, preview, development)

**Note**: After Terraform runs, manually redeploy Vercel to pick up the new environment variable.

### 5. Set Other Terraform Variables (Optional)

You can set variables via:

**Option A: Terraform Cloud UI**
Navigate to Variables tab in your workspace and add:
- `aws_region` = `us-east-1`
- `project_name` = `langgraph`
- `ecs_desired_count` = `1`
- etc.

**Option B: terraform.tfvars file (less recommended for cloud)**
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
```
Terraform Cloud will use these values when running remotely.

**Option C: Variable sets in Terraform Cloud**
Create a variable set for reusable variables across workspaces.

### 6. Review the Plan

```bash
terraform plan
```

**Note**: The plan runs **remotely** in Terraform Cloud, not on your local machine.

Review the resources that will be created:
- 1 VPC with subnets, NAT Gateway, Internet Gateway
- 1 Application Load Balancer with target group
- 1 ECS Cluster with Fargate service (1-4 tasks)
- 3 AWS Secrets Manager secrets (with your API keys from Terraform variables)
- 1 ECR Repository with lifecycle policy
- IAM roles and security groups
- CloudWatch log group
- Auto-scaling policies
- **Vercel environment variable** (NEXT_PUBLIC_WEBSOCKET_URL)

### 7. Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted.

**Deployment time**: ~5-7 minutes

You can watch the progress in:
- Terminal (live streaming from Terraform Cloud)
- Terraform Cloud UI (detailed run logs)

**After deployment:**
- ALB is created with a DNS name
- AWS Secrets Manager secrets are created with your API keys
- Vercel environment variable `NEXT_PUBLIC_WEBSOCKET_URL` is automatically set to the ALB URL

### 8. Build and Push Docker Image

After deployment completes, get the ECR URL from outputs:

```bash
terraform output ecr_repository_url
```

Then build and push:

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $(terraform output -raw ecr_repository_url | cut -d'/' -f1)

# Build and push (from project root)
cd ..
docker build -t langgraph:latest .
docker tag langgraph:latest $(cd infra && terraform output -raw ecr_repository_url):latest
docker push $(cd infra && terraform output -raw ecr_repository_url):latest
```

Or use the output command directly:
```bash
cd infra
terraform output -raw docker_build_commands | bash
```

### 9. Verify Secrets in AWS (Optional)

You can verify that your API keys were successfully injected into AWS Secrets Manager:

```bash
# List secrets
aws secretsmanager list-secrets --region us-east-1 | grep langgraph

# Get secret value (will show the actual key)
aws secretsmanager get-secret-value \
  --secret-id langgraph/llama-api-key \
  --region us-east-1 \
  --query SecretString \
  --output text
```

**Note**: Your API keys were already set via Terraform Cloud variables, so no manual secret updates are needed.

### 10. Redeploy Vercel

After Terraform sets the environment variable, redeploy Vercel to pick up the changes:

**Option A: Via CLI:**
```bash
vercel --prod
```

**Option B: Via UI:**
1. Go to Vercel project → Deployments
2. Find latest deployment
3. Click "..." → "Redeploy"

**Verify env var was set:**
```bash
terraform output vercel_env_var_set
```

### 11. Test Your Deployment

```bash
# Get ALB URL
ALB_URL=$(terraform output -raw alb_url)

# Test health endpoint
curl $ALB_URL/health

# Open in browser
open $ALB_URL
```

### 12. Use Environment Variable in Your Frontend

After Vercel redeploys, your Next.js frontend can access the WebSocket URL:

```typescript
// In your Next.js components or pages
const websocketUrl = process.env.NEXT_PUBLIC_WEBSOCKET_URL;

// Example: Connect to WebSocket
const ws = new WebSocket(`${websocketUrl}/ws`);

ws.onopen = () => {
  console.log('Connected to WebSocket');
};
```

**Note**: The `NEXT_PUBLIC_` prefix makes the variable available in the browser.

## Outputs

After `terraform apply`, important values are displayed:

```bash
# View all outputs
terraform output

# Specific outputs
terraform output alb_dns_name              # ALB URL for your backend
terraform output ecr_repository_url        # Docker registry URL
terraform output cloudwatch_log_group      # CloudWatch logs location
terraform output vercel_env_var_set        # Confirms Vercel env var was set
terraform output vercel_redeploy_instructions  # How to redeploy Vercel
```

**Key outputs:**
- `alb_dns_name`: The AWS Load Balancer URL (also pushed to Vercel)
- `vercel_env_var_set`: Confirmation that NEXT_PUBLIC_WEBSOCKET_URL was set in Vercel
- `docker_build_commands`: Copy-paste commands to build and push your Docker image
- `secrets_to_update`: Names of the AWS Secrets Manager secrets containing your API keys

## Terraform Cloud Features

### Remote Execution

All `terraform plan` and `terraform apply` commands run in Terraform Cloud, not locally. Benefits:
- ✅ Consistent environment
- ✅ No local AWS credentials needed (configured in workspace)
- ✅ Audit logs of all changes
- ✅ Team collaboration ready

### State Management

State is automatically stored in Terraform Cloud:
- ✅ Automatic locking (no DynamoDB needed)
- ✅ State versioning (rollback capability)
- ✅ Encrypted at rest
- ✅ View state in UI

### Viewing State

View state in Terraform Cloud UI:
1. Navigate to workspace
2. Click "States" tab
3. View current state or historical versions

Or via CLI:
```bash
terraform show
```

### Rolling Back

If you need to rollback:
1. Go to Terraform Cloud workspace → States
2. Find the previous good state version
3. Click "..." → "Download"
4. Restore if needed (or revert code and re-apply)

## Updating the Application

### Update Code and Redeploy

```bash
# 1. Build new image
cd ..
docker build -t langgraph:v1.1 .

# 2. Tag for ECR
ECR_URL=$(cd infra && terraform output -raw ecr_repository_url)
docker tag langgraph:v1.1 $ECR_URL:v1.1
docker tag langgraph:v1.1 $ECR_URL:latest

# 3. Push both tags
docker push $ECR_URL:v1.1
docker push $ECR_URL:latest

# 4. Force ECS service update
aws ecs update-service \
  --cluster langgraph-cluster \
  --service langgraph-service \
  --force-new-deployment \
  --region us-east-1
```

### Update Infrastructure

```bash
# 1. Edit Terraform files or variables in Terraform Cloud UI

# 2. Plan changes
terraform plan

# 3. Apply changes
terraform apply
```

## Monitoring

### View Logs

```bash
# Get log group name
LOG_GROUP=$(terraform output -raw cloudwatch_log_group)

# Tail logs
aws logs tail $LOG_GROUP --follow --region us-east-1

# Filter for errors
aws logs tail $LOG_GROUP --follow --filter-pattern "ERROR" --region us-east-1
```

### Check Service Health

```bash
# ECS service status
aws ecs describe-services \
  --cluster langgraph-cluster \
  --services langgraph-service \
  --region us-east-1 \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

# Task status
aws ecs list-tasks \
  --cluster langgraph-cluster \
  --service-name langgraph-service \
  --region us-east-1
```

### CloudWatch Metrics

View in AWS Console:
- ECS → Clusters → langgraph-cluster → Metrics
- EC2 → Load Balancers → langgraph-alb → Monitoring

Key metrics:
- **CPUUtilization**: Target < 70%
- **MemoryUtilization**: Monitor for leaks
- **HealthyHostCount**: Should equal desired count
- **TargetResponseTime**: WebSocket connection time

### Terraform Cloud Run History

View all infrastructure changes:
1. Go to Terraform Cloud workspace
2. Click "Runs" tab
3. See history of all plans and applies with:
   - Who triggered the run
   - What changed
   - Complete logs
   - State before/after

## Scaling

### Manual Scaling

```bash
# Scale to 2 tasks
aws ecs update-service \
  --cluster langgraph-cluster \
  --service langgraph-service \
  --desired-count 2 \
  --region us-east-1
```

### Auto Scaling

Auto-scaling is configured based on CPU:
- **Target**: 70% CPU utilization
- **Min**: 1 task
- **Max**: 4 tasks
- **Scale out**: 60 second cooldown
- **Scale in**: 300 second cooldown

Modify via Terraform Cloud variables or local `terraform.tfvars`:
```hcl
ecs_min_capacity = 2
ecs_max_capacity = 10
ecs_cpu_target   = 60
```

Then `terraform apply`.

## Cost Estimation

**Monthly costs** (us-east-1):

| Resource | Configuration | Cost |
|----------|--------------|------|
| ECS Fargate | 1 task × 0.5 vCPU × 1 GB | ~$15 |
| NAT Gateway | 1 gateway + data | ~$35 |
| ALB | 1 load balancer | ~$20 |
| Data Transfer | 50 GB out | ~$5 |
| CloudWatch Logs | 5 GB/month | ~$3 |
| Secrets Manager | 3 secrets | ~$1.20 |
| **Terraform Cloud** | Free tier | $0 |
| **Total** | | **~$79/month** |

**Terraform Cloud pricing**:
- **Free**: Up to 500 resources, unlimited users
- **Team**: $20/user/month (additional features)
- **Business**: Custom pricing

**Cost optimization tips**:
- Run 1 task outside business hours
- Use VPC endpoints to reduce NAT costs
- Reduce log retention (currently 7 days)
- Consider Fargate Spot for non-production

## Advanced Configuration

### OIDC with AWS (No Static Credentials)

**Recommended for production deployments.**

Instead of storing AWS access keys in Terraform Cloud, use OIDC (OpenID Connect) for dynamic, temporary credentials that automatically rotate.

#### Quick Setup (Automated)

We provide a script that automates the entire OIDC setup:

```bash
cd infra/scripts
./setup-oidc.sh --org YOUR_ORG --workspace YOUR_WORKSPACE
```

The script will:
1. Create an OIDC identity provider in AWS IAM (if not exists)
2. Create an IAM role with trust policy for your Terraform Cloud workspace
3. Attach IAM permissions (default: AdministratorAccess)
4. Output the role ARN for Terraform Cloud configuration

**Full documentation:** See [scripts/README.md](scripts/README.md) for detailed instructions, troubleshooting, and security best practices.

#### Manual Setup

If you prefer manual setup:

1. **Create OIDC Provider in AWS:**
   ```bash
   aws iam create-open-id-connect-provider \
     --url https://app.terraform.io \
     --client-id-list aws.workload.identity \
     --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280
   ```

2. **Create IAM Role with Trust Policy:**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": {
         "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/app.terraform.io"
       },
       "Action": "sts:AssumeRoleWithWebIdentity",
       "Condition": {
         "StringEquals": {
           "app.terraform.io:aud": "aws.workload.identity"
         },
         "StringLike": {
           "app.terraform.io:sub": "organization:YOUR_ORG:project:*:workspace:YOUR_WORKSPACE:run_phase:*"
         }
       }
     }]
   }
   ```

3. **Configure Terraform Cloud:**
   - Go to workspace → Settings → Authentication
   - Enable AWS dynamic credentials
   - Set role ARN from step 2

**Official Documentation:** https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration

### Variable Sets

Create reusable variable sets for multiple workspaces:

1. Terraform Cloud UI → Settings → Variable Sets
2. Create new set (e.g., "AWS Credentials")
3. Add variables
4. Apply to multiple workspaces

### Notifications

Set up notifications for run status:

1. Workspace → Settings → Notifications
2. Add notification destination:
   - Slack
   - Microsoft Teams
   - Email
   - Generic webhook

### Policy as Code (Sentinel)

Enforce compliance policies (Team/Business tier):

Example policy:
```hcl
# Ensure all resources are tagged
import "tfplan/v2" as tfplan

main = rule {
  all tfplan.resource_changes as _, rc {
    rc.change.after.tags contains "Project"
  }
}
```

## Troubleshooting

### Tasks Not Starting

```bash
# Check task status
aws ecs describe-tasks \
  --cluster langgraph-cluster \
  --tasks $(aws ecs list-tasks --cluster langgraph-cluster --service-name langgraph-service --query 'taskArns[0]' --output text) \
  --region us-east-1
```

Common issues:
- **Image pull error**: Check ECR permissions and image exists
- **Secrets error**: Verify API keys are set as Terraform variables in Terraform Cloud (see step 4)
- **Health check failing**: Check application logs

### Health Check Failing

```bash
# View logs
aws logs tail /ecs/langgraph --follow --region us-east-1

# Check if port 8010 is listening
# (from inside container)
curl http://localhost:8010/health
```

### Terraform Cloud Connection Issues

```bash
# Check if logged in
terraform login

# Force re-login
rm -rf ~/.terraform.d/credentials.tfrc.json
terraform login

# Check workspace exists
terraform workspace list
```

### Plan/Apply Failing

Check Terraform Cloud run logs:
1. Go to workspace → Runs
2. Click on failed run
3. View detailed error logs
4. Common issues:
   - AWS credentials not set
   - Insufficient IAM permissions
   - Resource conflicts
   - Vercel API token not set or invalid
   - Invalid Vercel project ID

### Vercel Integration Issues

**Environment variable not showing in Vercel:**

1. Check Terraform output:
   ```bash
   terraform output vercel_env_var_set
   ```

2. Verify manually in Vercel UI:
   - Go to Project → Settings → Environment Variables
   - Look for `NEXT_PUBLIC_WEBSOCKET_URL`

3. Common issues:
   - **Wrong project ID**: Double-check in Vercel Settings → General
   - **Missing API token**: Ensure `VERCEL_API_TOKEN` is set in Terraform Cloud
   - **Team ID mismatch**: If using team projects, verify `vercel_team_id`
   - **Token permissions**: Ensure token has write access to project

**Frontend can't connect to WebSocket:**

1. Verify env var value:
   ```bash
   # Check what was set
   terraform output vercel_env_var_set
   ```

2. Redeploy Vercel:
   ```bash
   vercel --prod
   ```

3. Test WebSocket endpoint:
   ```bash
   curl http://YOUR_ALB_URL/health
   ```

4. Check CORS if using custom domain

## Cleanup

**Warning**: This will destroy all infrastructure.

```bash
# Destroy infrastructure (runs remotely in Terraform Cloud)
terraform destroy
```

You'll need to confirm in the terminal.

**Note**: Terraform Cloud retains state history even after destroy. You can view previous states in the UI.

### Delete Workspace (Optional)

After destroying resources, if you want to delete the Terraform Cloud workspace:

1. Terraform Cloud UI → Workspace settings
2. Scroll to "Destruction and Deletion"
3. Click "Delete workspace"

Or via CLI:
```bash
terraform workspace delete langgraph-websocket
```

## Security Best Practices

✅ **Implemented**:
- Private subnets for ECS tasks
- Secrets Manager for API keys
- IAM roles with least privilege
- Security groups with minimal access
- Terraform Cloud for state (encrypted at rest)
- No hard-coded secrets
- Container health checks

🔒 **Recommended additions**:
- HTTPS listener with ACM certificate
- WAF for ALB
- VPC Flow Logs
- GuardDuty for threat detection
- AWS Config for compliance
- OIDC authentication (no static AWS credentials)
- Sentinel policies for compliance (Terraform Cloud Team tier)

## Team Collaboration

### Inviting Team Members

1. Terraform Cloud → Organization Settings → Teams
2. Create team
3. Invite members
4. Assign workspace permissions:
   - **Read**: View state and runs
   - **Plan**: Trigger plans
   - **Write**: Trigger applies
   - **Admin**: Full control

### Remote State Sharing

Share outputs with other workspaces:

```hcl
# In another Terraform workspace
data "terraform_remote_state" "langgraph" {
  backend = "remote"

  config = {
    organization = "your-org"
    workspaces = {
      name = "langgraph-websocket"
    }
  }
}

# Use outputs
output "langgraph_alb" {
  value = data.terraform_remote_state.langgraph.outputs.alb_dns_name
}
```

## Files

```
infra/
├── backend.tf                    # Terraform Cloud configuration
├── main.tf                       # All infrastructure resources
├── variables.tf                  # Input variables
├── outputs.tf                    # Output values
├── terraform.tfvars.example      # Example configuration
├── README.md                     # This file
└── scripts/
    ├── setup-oidc.sh             # Automated OIDC setup for AWS
    └── README.md                 # OIDC setup documentation
```

## Support

For issues:
1. Check Terraform Cloud run logs
2. Check CloudWatch logs
3. Review ECS task status
4. Verify security group rules
5. Verify API keys are set in Terraform Cloud variables
6. Check ALB target health

## Resources

- [Terraform Cloud Documentation](https://developer.hashicorp.com/terraform/cloud-docs)
- [AWS ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Vercel Terraform Provider](https://registry.terraform.io/providers/vercel/vercel/latest/docs)
- [Vercel Environment Variables Guide](https://vercel.com/docs/projects/environment-variables)

## Next Steps

Once deployed, consider:

**Immediate improvements:**
1. **SSL/TLS**: Add HTTPS with ACM certificate for secure WebSocket (wss://)
2. **Custom Domain**: Configure Route53 or Cloudflare DNS pointing to ALB
3. **Monitoring**: Set up CloudWatch alarms for task failures and high CPU

**Production hardening:**
4. **CI/CD**: Automate deployments with GitHub Actions + Terraform Cloud
5. **Backup**: Enable ECS service deployment circuit breaker
6. **WAF**: Add Web Application Firewall for ALB protection
7. **Cost Optimization**: Set up AWS budgets and alerts

**Scaling:**
8. **Phase 2**: Migrate to Celery + Redis when traffic increases
9. **Caching**: Add ElastiCache for session management
10. **Policy as Code**: Implement Sentinel policies for compliance (Terraform Cloud Team tier)

**Vercel Integration:**
- ✅ Environment variable automation complete
- Next: Update Vercel domain to use custom domain with SSL
