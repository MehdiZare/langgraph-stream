# Automation Guide: IAM User Creation

This guide explains the automated options for creating the IAM user required for GitHub Actions and Terraform Cloud.

## Why Automate?

Manual IAM user creation through the AWS Console is:
- Time-consuming (10-15 minutes)
- Error-prone (copy-paste mistakes in policies)
- Not reproducible
- Hard to version control

Automated creation is:
- Fast (< 2 minutes)
- Consistent
- Reproducible
- Version controlled

## Option 1: Terraform (Recommended)

### Advantages
- Infrastructure as Code
- State tracking
- Easy credential rotation
- Declarative configuration

### Usage

```bash
cd infra/bootstrap

# Initialize
terraform init

# Review
terraform plan

# Create
terraform apply

# Get credentials
terraform output access_key_id
terraform output -raw secret_access_key
```

### What It Creates
- IAM policy with scoped permissions
- IAM user in `/automation/` path
- Access keys for programmatic access
- Tags for organization

### Rotating Credentials

```bash
cd infra/bootstrap

# Recreate access key
terraform apply -replace=aws_iam_access_key.github_terraform_deployer

# Get new credentials
terraform output access_key_id
terraform output -raw secret_access_key

# Update in Terraform Cloud and GitHub
```

### Cleanup

```bash
cd infra/bootstrap
terraform destroy
```

## Option 2: AWS CLI Script

### Advantages
- No Terraform knowledge needed
- Interactive prompts
- Immediate feedback
- Can save credentials to file

### Usage

```bash
cd infra/bootstrap
./create-iam-user.sh
```

The script will:
1. Check AWS CLI configuration
2. Create IAM policy
3. Create IAM user
4. Attach policy to user
5. Create access keys
6. Display credentials
7. Optionally save to file

### Customization

Set environment variables before running:

```bash
export PROJECT_NAME="my-project"
export IAM_USER_NAME="my-deployer"
export AWS_REGION="us-west-2"

./create-iam-user.sh
```

### What It Outputs

```
======================================================================
IAM USER CREATED SUCCESSFULLY
======================================================================

User Name: github-terraform-deployer
User ARN:  arn:aws:iam::123456789012:user/automation/github-terraform-deployer
Policy:    arn:aws:iam::123456789012:policy/roboad-backend-terraform-deployer-policy

IMPORTANT: Save these credentials securely! They won't be shown again.

Access Key ID:     AKIA...
Secret Access Key: wJal...

======================================================================
Next Steps:
======================================================================

1. Add to Terraform Cloud workspaces
2. Add to GitHub Secrets
3. Store in password manager
```

## Option 3: Manual (AWS Console)

See `SETUP.md` Step 1, Option C for detailed manual steps.

Use this if:
- You don't have AWS CLI configured
- You prefer GUI interfaces
- You need to review each step visually

## Comparison

| Feature | Terraform | AWS CLI Script | Manual |
|---------|-----------|----------------|--------|
| Speed | ⚡⚡⚡ | ⚡⚡ | ⚡ |
| Reproducible | ✅ | ✅ | ❌ |
| Version Control | ✅ | ✅ | ❌ |
| State Tracking | ✅ | ❌ | ❌ |
| Easy Rotation | ✅ | ✅ | ❌ |
| No Tools Needed | ❌ | ❌ | ✅ |
| Interactive | ❌ | ✅ | ✅ |

## Security Best Practices

### After Creation

1. **Store credentials securely**
   - Password manager (1Password, LastPass)
   - AWS Secrets Manager
   - HashiCorp Vault

2. **Set up rotation**
   - Rotate every 90 days
   - Use calendar reminders
   - Automate with AWS Lambda (optional)

3. **Monitor usage**
   - Enable CloudTrail
   - Set up CloudWatch alarms
   - Review IAM Access Advisor

4. **Restrict permissions**
   - Use least-privilege principle
   - Scope IAM role creation to project
   - Don't use `*` for IAM actions

### Verifying Credentials

Test the newly created credentials:

```bash
# Configure profile
aws configure --profile terraform-deployer
# Enter Access Key ID and Secret

# Test
aws sts get-caller-identity --profile terraform-deployer

# Should output:
# {
#   "UserId": "AIDAXXXXXXXXXX",
#   "Account": "123456789012",
#   "Arn": "arn:aws:iam::123456789012:user/automation/github-terraform-deployer"
# }

# Test permissions
aws ecs list-clusters --profile terraform-deployer --region us-east-2
```

## Troubleshooting

### Terraform: "User already exists"

```bash
cd infra/bootstrap

# Import existing user
terraform import aws_iam_user.github_terraform_deployer github-terraform-deployer

# Then apply
terraform apply
```

### Script: "jq: command not found"

Install jq:

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# Amazon Linux
sudo yum install jq
```

### "Not authorized to perform iam:CreateUser"

Your current AWS credentials don't have permission to create IAM resources. Options:

1. Use AWS account root credentials (not recommended)
2. Assume an admin role
3. Ask your AWS administrator
4. Add temporary IAM permissions to your user

### Multiple Access Keys

AWS allows max 2 access keys per user. If you see "LimitExceeded":

```bash
# List existing keys
aws iam list-access-keys --user-name github-terraform-deployer

# Delete old key
aws iam delete-access-key \
  --user-name github-terraform-deployer \
  --access-key-id AKIA...

# Then retry
```

## Advanced: OIDC Alternative

Instead of static credentials, consider OIDC for dynamic, temporary credentials:

### GitHub Actions OIDC

```yaml
# .github/workflows/deploy.yml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsRole
          aws-region: us-east-2
```

### Terraform Cloud Dynamic Credentials

Configure in Terraform Cloud workspace settings:
- Enable AWS dynamic credentials
- Set IAM role ARN
- Terraform Cloud assumes role automatically

**Benefits**:
- No static credentials to manage
- Automatic rotation
- Better audit trail
- Enhanced security

**See**: `infra/bootstrap/README.md` for OIDC setup details

## Integration Steps

After creating IAM user (any method), follow these steps:

### 1. Add to Terraform Cloud

For each workspace (`roboad-fast-ws-shared`, `roboad-fast-ws-prod`):

1. Go to workspace → Variables
2. Add environment variables (mark sensitive):
   - Key: `AWS_ACCESS_KEY_ID`
   - Value: (from output)
   - Key: `AWS_SECRET_ACCESS_KEY`
   - Value: (from output)

### 2. Add to GitHub Secrets

1. Go to repo → Settings → Secrets and variables → Actions
2. Add repository secrets:
   - Name: `AWS_ACCESS_KEY_ID`
   - Value: (from output)
   - Name: `AWS_SECRET_ACCESS_KEY`
   - Value: (from output)

### 3. Verify Integration

**Test Terraform Cloud**:
```bash
cd infra/environments/shared
terraform init
terraform plan
# Should succeed without credential errors
```

**Test GitHub Actions**:
- Push to a branch
- Create a PR
- Watch GitHub Actions run
- PR environment should deploy successfully

## Maintenance

### Monthly Review

- [ ] Check CloudTrail for unexpected API calls
- [ ] Review IAM Access Advisor for unused permissions
- [ ] Verify access keys are still needed
- [ ] Check for security advisories

### Quarterly Rotation

```bash
# With Terraform
cd infra/bootstrap
terraform apply -replace=aws_iam_access_key.github_terraform_deployer
terraform output access_key_id
terraform output -raw secret_access_key

# Update in Terraform Cloud and GitHub
```

### Decommissioning

When no longer needed:

```bash
# With Terraform
cd infra/bootstrap
terraform destroy

# Or with AWS CLI
aws iam delete-access-key --user-name github-terraform-deployer --access-key-id AKIA...
aws iam detach-user-policy --user-name github-terraform-deployer --policy-arn arn:aws:iam::...:policy/...
aws iam delete-user --user-name github-terraform-deployer
aws iam delete-policy --policy-arn arn:aws:iam::...:policy/...
```

## Files Reference

```
infra/bootstrap/
├── iam-user.tf           # Terraform configuration
├── variables.tf          # Terraform variables
├── create-iam-user.sh   # Bash script alternative
└── README.md            # Detailed documentation
```

## Support

For issues:
1. Check `infra/bootstrap/README.md` for detailed docs
2. Review Terraform/AWS CLI logs
3. Verify AWS credentials used for bootstrap have IAM permissions
4. Check AWS service health dashboard

---

**Recommended**: Use Terraform option for production deployments. Use script for quick testing or proof-of-concepts.
