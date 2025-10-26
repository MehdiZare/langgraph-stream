# Bootstrap IAM User for GitHub Actions & Terraform Cloud

This directory contains Terraform configuration to create the IAM user required for GitHub Actions and Terraform Cloud automation.

## What This Creates

- IAM user: `github-terraform-deployer`
- Custom IAM policy with permissions to manage:
  - EC2 (VPC, subnets, security groups)
  - ECS (clusters, services, task definitions)
  - ECR (container registry)
  - ELB/ALB (load balancers)
  - CloudWatch Logs
  - Secrets Manager
  - Application Auto Scaling
  - IAM roles (scoped to project)
- Access key for programmatic access

## Prerequisites

You need AWS credentials with permissions to:
- Create IAM users
- Create IAM policies
- Create access keys

Use your **personal AWS credentials** or **admin credentials** to run this bootstrap.

## Option 1: Using Terraform (Recommended)

### Step 1: Configure Your AWS Credentials

```bash
# Option A: AWS CLI configure
aws configure

# Option B: Environment variables
export AWS_ACCESS_KEY_ID="your-admin-access-key"
export AWS_SECRET_ACCESS_KEY="your-admin-secret-key"
export AWS_DEFAULT_REGION="us-east-2"

# Option C: AWS SSO
aws sso login --profile your-profile
export AWS_PROFILE=your-profile
```

### Step 2: Run Terraform

```bash
cd infra/bootstrap

# Initialize
terraform init

# Review what will be created
terraform plan

# Create the IAM user and policy
terraform apply
```

### Step 3: Save the Credentials

**IMPORTANT**: Save these credentials immediately!

```bash
# View credentials (they won't be shown again)
terraform output access_key_id
terraform output secret_access_key

# Or save to a file (encrypted!)
terraform output -raw access_key_id > access_key.txt
terraform output -raw secret_access_key > secret_key.txt
```

**Store in**:
- Password manager (1Password, LastPass, etc.)
- AWS Secrets Manager
- GitHub Secrets (for the workflows)
- Terraform Cloud variables (for the workspaces)

### Step 4: Configure Terraform Cloud

For each workspace (`roboad-fast-ws-shared`, `roboad-fast-ws-prod`):

1. Go to workspace → Variables
2. Add environment variables (mark as sensitive):
   - `AWS_ACCESS_KEY_ID` = (from terraform output)
   - `AWS_SECRET_ACCESS_KEY` = (from terraform output)

### Step 5: Configure GitHub Secrets

1. Go to GitHub repo → Settings → Secrets and variables → Actions
2. Add repository secrets:
   - `AWS_ACCESS_KEY_ID` = (from terraform output)
   - `AWS_SECRET_ACCESS_KEY` = (from terraform output)

### Step 6: Clean Up Bootstrap Files

```bash
# Remove credentials from local files
rm -f access_key.txt secret_key.txt

# Optional: Delete local state (credentials are saved elsewhere)
# rm terraform-bootstrap.tfstate*
```

## Option 2: Using AWS CLI Script

If you prefer a bash script instead of Terraform:

```bash
cd infra/bootstrap
./create-iam-user.sh
```

The script will:
1. Create the IAM policy
2. Create the IAM user
3. Attach the policy to the user
4. Create access keys
5. Display the credentials

## Customization

### Change IAM User Name

Edit `variables.tf`:
```hcl
variable "iam_user_name" {
  default     = "my-custom-deployer-name"
}
```

### Modify Permissions

Edit `iam-user.tf` and adjust the policy JSON in `aws_iam_policy.terraform_deployer`.

**Security Best Practices**:
- Use least-privilege permissions
- Scope IAM role creation to project prefix
- Don't grant `*` on IAM actions
- Consider using AWS Organizations for additional boundaries

## Verification

Test the credentials:

```bash
# Configure AWS CLI with new credentials
aws configure --profile terraform-deployer

# Test access
aws sts get-caller-identity --profile terraform-deployer

# Should return:
# {
#   "UserId": "AIDAXXXXXXXXXX",
#   "Account": "123456789012",
#   "Arn": "arn:aws:iam::123456789012:user/automation/github-terraform-deployer"
# }

# Test permissions
aws ecs list-clusters --profile terraform-deployer --region us-east-2
```

## Rotating Credentials

To rotate the access keys:

```bash
cd infra/bootstrap

# This will destroy and recreate the access key
terraform apply -replace=aws_iam_access_key.github_terraform_deployer

# Get new credentials
terraform output access_key_id
terraform output secret_access_key

# Update in Terraform Cloud and GitHub Secrets
```

## Deleting the IAM User

If you need to delete everything:

```bash
cd infra/bootstrap
terraform destroy
```

**Warning**: This will delete the IAM user and access keys. Make sure you're not using these credentials anywhere before destroying.

## Troubleshooting

### Error: "User already exists"

If the user already exists from a previous run:

```bash
# Import existing user
terraform import aws_iam_user.github_terraform_deployer github-terraform-deployer

# Then apply
terraform apply
```

### Error: "Not authorized to perform iam:CreateUser"

Your current AWS credentials don't have permission to create IAM users. Use credentials with IAM admin access.

### Credentials Not Working

1. Verify credentials are active:
   ```bash
   aws iam list-access-keys --user-name github-terraform-deployer
   ```

2. Check policy is attached:
   ```bash
   aws iam list-attached-user-policies --user-name github-terraform-deployer
   ```

3. Test with AWS CLI:
   ```bash
   aws sts get-caller-identity
   ```

## Security Notes

✅ **Best Practices**:
- Store credentials in secrets manager
- Rotate keys every 90 days
- Use least-privilege permissions
- Enable CloudTrail for audit logging
- Consider using AWS IAM Identity Center (SSO) for human access

⚠️ **Avoid**:
- Committing credentials to git
- Sharing credentials via email/Slack
- Using admin credentials for automation
- Leaving old access keys active

## Alternative: OIDC (No Static Credentials)

For enhanced security, consider using OIDC instead of static credentials:

- **GitHub Actions**: Use OIDC provider for GitHub
- **Terraform Cloud**: Use dynamic provider credentials

See main SETUP.md for OIDC configuration.
