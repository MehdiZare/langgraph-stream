# Shared Workspace Cleanup Guide

## Problem

The Terraform Cloud workspace `roboad-fast-ws-shared` has corrupted state from the Cloudflare provider v4 to v5 upgrade. The state contains old `cloudflare_record` resources that v5 doesn't recognize, causing errors:

```
Error: no schema available for cloudflare_record.cert_validation while reading state
Error: Unsupported attribute - This object does not have an attribute named "hostname"
```

The workspace cannot plan or destroy because the state is unreadable by the new provider.

## Solution: Manual Cleanup + Force Delete

Since the state is too corrupted to run Terraform operations, we need to:
1. **Manually clean up AWS resources** (so they don't get orphaned)
2. **Force delete the workspace** (bypassing state checks)
3. **Fresh deployment** with v5-compatible code

## Step-by-Step Instructions

### Step 1: List Current AWS Resources

First, see what AWS resources exist in the shared environment:

```bash
cd scripts
./list-shared-resources.sh
```

This will show you:
- VPC and networking components
- ACM certificates
- IAM roles
- Secrets Manager secrets
- S3 buckets
- ECR repositories
- CloudWatch log groups

**Take a screenshot or save this output** - you'll want to verify these are cleaned up.

### Step 2: Clean Up AWS Resources

You have two options:

#### Option A: Use AWS Console (Recommended for visibility)

Go to the AWS Console and manually delete resources in this order:

1. **ACM Certificate** (us-east-2)
   - Go to Certificate Manager
   - Delete certificate for `*.roboad.ai`

2. **NAT Gateways** (if any)
   - EC2 → NAT Gateways
   - Delete NAT gateways (they cost money!)
   - Release associated Elastic IPs

3. **VPC and Components**
   - EC2 → Your VPCs
   - Select the `roboad-backend` VPC
   - Actions → Delete VPC (this cleans up subnets, route tables, IGW automatically)

4. **IAM Roles**
   - IAM → Roles
   - Delete roles with `roboad-backend` prefix:
     - `roboad-backend-ecs-task-execution-role`
     - `roboad-backend-ecs-task-role`

5. **Secrets Manager**
   - Secrets Manager → Secrets
   - Delete secrets with `roboad-backend` prefix
   - Use 7-day recovery window or force delete

6. **CloudWatch Log Groups**
   - CloudWatch → Log groups
   - Delete `/ecs/roboad-backend` log group

7. **S3 Buckets** (if any for scans)
   - S3 → Buckets
   - Empty and delete buckets with `roboad` prefix

**KEEP:** ECR repository (`roboad-backend`) - contains your Docker images!

#### Option B: Use AWS CLI Commands

```bash
# Set your region
export AWS_REGION=us-east-2
export PROJECT_PREFIX=roboad-backend

# 1. Delete ACM Certificate
CERT_ARN=$(aws acm list-certificates --region $AWS_REGION \
  --query 'CertificateSummaryList[?DomainName==`*.roboad.ai`].CertificateArn' \
  --output text)
if [ ! -z "$CERT_ARN" ]; then
  aws acm delete-certificate --region $AWS_REGION --certificate-arn $CERT_ARN
fi

# 2. Delete NAT Gateways (they cost money!)
NAT_IDS=$(aws ec2 describe-nat-gateways --region $AWS_REGION \
  --filter "Name=tag:Project,Values=${PROJECT_PREFIX}" \
  --query 'NatGateways[?State==`available`].NatGatewayId' --output text)
for NAT_ID in $NAT_IDS; do
  aws ec2 delete-nat-gateway --region $AWS_REGION --nat-gateway-id $NAT_ID
done

# Wait for NAT gateways to delete (takes a few minutes)
sleep 120

# 3. Release Elastic IPs associated with NAT gateways
EIP_ALLOCS=$(aws ec2 describe-addresses --region $AWS_REGION \
  --query 'Addresses[?contains(Tags[?Key==`Project`].Value, `'${PROJECT_PREFIX}'`)].AllocationId' \
  --output text)
for EIP_ALLOC in $EIP_ALLOCS; do
  aws ec2 release-address --region $AWS_REGION --allocation-id $EIP_ALLOC
done

# 4. Delete VPC (this cleans up subnets, route tables, IGW, security groups)
VPC_ID=$(aws ec2 describe-vpcs --region $AWS_REGION \
  --filters "Name=tag:Project,Values=${PROJECT_PREFIX}" \
  --query 'Vpcs[0].VpcId' --output text)
if [ ! -z "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
  aws ec2 delete-vpc --region $AWS_REGION --vpc-id $VPC_ID
fi

# 5. Delete IAM Roles
aws iam delete-role-policy --role-name ${PROJECT_PREFIX}-ecs-task-execution-role \
  --policy-name ecs-task-execution-policy 2>/dev/null || true
aws iam delete-role --role-name ${PROJECT_PREFIX}-ecs-task-execution-role 2>/dev/null || true

aws iam delete-role-policy --role-name ${PROJECT_PREFIX}-ecs-task-role \
  --policy-name ecs-task-policy 2>/dev/null || true
aws iam delete-role --role-name ${PROJECT_PREFIX}-ecs-task-role 2>/dev/null || true

# 6. Delete Secrets
for SECRET_ARN in $(aws secretsmanager list-secrets --region $AWS_REGION \
  --query 'SecretList[?contains(Name, `'${PROJECT_PREFIX}'`)].ARN' --output text); do
  aws secretsmanager delete-secret --region $AWS_REGION \
    --secret-id $SECRET_ARN --force-delete-without-recovery
done

# 7. Delete CloudWatch Log Groups
for LOG_GROUP in $(aws logs describe-log-groups --region $AWS_REGION \
  --log-group-name-prefix "/ecs/${PROJECT_PREFIX}" \
  --query 'logGroups[].logGroupName' --output text); do
  aws logs delete-log-group --region $AWS_REGION --log-group-name $LOG_GROUP
done

# 8. Delete S3 Buckets (if any)
for BUCKET in $(aws s3api list-buckets \
  --query 'Buckets[?contains(Name, `'${PROJECT_PREFIX}'`)].Name' --output text); do
  aws s3 rm s3://$BUCKET --recursive
  aws s3api delete-bucket --bucket $BUCKET
done
```

### Step 3: Verify AWS Resources Are Deleted

Run the list script again to confirm:

```bash
./list-shared-resources.sh
```

You should see mostly empty results (except ECR repository).

### Step 4: Force Delete Terraform Cloud Workspace

Now that AWS resources are cleaned up, delete the corrupted workspace:

```bash
# Set your Terraform Cloud API token
export TF_API_TOKEN='your_token_from_terraform_cloud'

# Run force delete script
./force-delete-shared-workspace.sh
```

The script will:
- Find the workspace
- Unlock it if locked
- Force delete without checking state
- Confirm deletion

### Step 5: Verify Workspace Is Gone

Check Terraform Cloud UI:
- Go to https://app.terraform.io/app/roboad/workspaces
- Verify `roboad-fast-ws-shared` is deleted

### Step 6: Trigger Fresh Deployment

The latest code (commits `5430e88` and `4e0a0f4`) has all Cloudflare v5 fixes applied:
- ✅ Uses `content` parameter instead of `value`
- ✅ Uses `record.name` instead of `record.hostname`
- ✅ Hardcoded zone ID workaround for v5 zone lookup issues

To create a fresh workspace:

1. **If using GitHub Actions:**
   - Push a new commit (even just a comment change)
   - Or manually trigger the workflow

2. **If using Terraform Cloud directly:**
   - The workspace will be auto-created on next run
   - Queue a new run in Terraform Cloud UI

### Step 7: Monitor New Deployment

Watch the deployment in Terraform Cloud:
- Workspace: `roboad-fast-ws-shared`
- Check for successful resource creation
- ACM certificate validation takes 5-30 minutes

Expected resources created:
- ✅ VPC with public/private subnets
- ✅ NAT gateways and internet gateway
- ✅ IAM roles for ECS tasks
- ✅ Secrets Manager secrets
- ✅ S3 bucket for scans
- ✅ ACM wildcard certificate (`*.roboad.ai`)
- ✅ Cloudflare DNS validation records
- ✅ CloudWatch log groups

## Troubleshooting

### "Workspace still exists"
- Check that you're using the correct API token
- Verify token has admin permissions for the organization

### "AWS resources not deleting"
- VPC delete fails if NAT gateways still exist (wait for them to delete)
- NAT gateway delete requires releasing Elastic IPs
- Security groups may have dependencies - delete manually in Console

### "New deployment fails with same error"
- Check that workspace was actually deleted
- Verify code has latest commits (`5430e88`, `4e0a0f4`)
- Check Terraform lock file has v5 provider versions

### "ACM certificate validation stuck"
- Check Cloudflare DNS records are created correctly
- DNS propagation can take 5-30 minutes
- Verify zone ID is correct: `37a732a3f8084c6331df47901dbc2cc5`

## What Gets Recreated

All resources will be recreated identically:
- **VPC:** Same CIDR blocks, same configuration
- **IAM Roles:** Same permissions
- **Secrets:** Same names (you'll need to update values after creation)
- **ACM Cert:** New certificate for `*.roboad.ai` (validated via DNS)
- **Log Groups:** Same names and retention policies

## Important Notes

1. **ECR Repository:** Not deleted - your Docker images are safe
2. **DNS Records:** Old Cloudflare records may need manual cleanup
3. **Secrets Values:** After recreation, update secret values in AWS Console
4. **Cost:** NAT gateways cost ~$0.045/hour - make sure they're deleted!

## Prevention

To avoid this in the future:
1. Test major provider upgrades in non-prod environments first
2. Use provider version constraints (`~> 4.44` instead of `~> 4.0`)
3. Read migration guides before upgrading
4. Consider gradual upgrades (v4.40 → v4.44 → v5.0)

## Need Help?

- Terraform Cloud: https://app.terraform.io/app/roboad/workspaces
- AWS Console: https://console.aws.amazon.com
- Cloudflare: https://dash.cloudflare.com
- Provider v5 Issues: https://github.com/cloudflare/terraform-provider-cloudflare/issues
