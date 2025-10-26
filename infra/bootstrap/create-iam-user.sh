#!/bin/bash

# ============================================================================
# Create IAM User for GitHub Actions & Terraform Cloud
# This script creates an IAM user with the necessary permissions
# ============================================================================

set -e  # Exit on error

# Configuration
PROJECT_NAME="${PROJECT_NAME:-roboad-backend}"
IAM_USER_NAME="${IAM_USER_NAME:-github-terraform-deployer}"
AWS_REGION="${AWS_REGION:-us-east-2}"
POLICY_NAME="${PROJECT_NAME}-terraform-deployer-policy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================================================"
echo "Creating IAM User for GitHub Actions & Terraform Cloud"
echo "======================================================================"
echo ""
echo "Configuration:"
echo "  Project Name: $PROJECT_NAME"
echo "  IAM User:     $IAM_USER_NAME"
echo "  Region:       $AWS_REGION"
echo ""

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not configured or credentials are invalid${NC}"
    echo "Please run 'aws configure' first"
    exit 1
fi

# Get current AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"
echo ""

# ============================================================================
# Step 1: Create IAM Policy
# ============================================================================

echo -e "${YELLOW}Step 1: Creating IAM Policy...${NC}"

POLICY_DOCUMENT=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ManageEC2",
      "Effect": "Allow",
      "Action": ["ec2:*"],
      "Resource": "*"
    },
    {
      "Sid": "ManageECS",
      "Effect": "Allow",
      "Action": ["ecs:*"],
      "Resource": "*"
    },
    {
      "Sid": "ManageECR",
      "Effect": "Allow",
      "Action": ["ecr:*"],
      "Resource": "*"
    },
    {
      "Sid": "ManageLoadBalancing",
      "Effect": "Allow",
      "Action": ["elasticloadbalancing:*"],
      "Resource": "*"
    },
    {
      "Sid": "ManageLogs",
      "Effect": "Allow",
      "Action": ["logs:*"],
      "Resource": "*"
    },
    {
      "Sid": "ManageSecrets",
      "Effect": "Allow",
      "Action": ["secretsmanager:*"],
      "Resource": "*"
    },
    {
      "Sid": "ManageAutoScaling",
      "Effect": "Allow",
      "Action": ["application-autoscaling:*"],
      "Resource": "*"
    },
    {
      "Sid": "ManageIAMRoles",
      "Effect": "Allow",
      "Action": [
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
      ],
      "Resource": ["arn:aws:iam::*:role/${PROJECT_NAME}-*"]
    },
    {
      "Sid": "ReadIAMPolicies",
      "Effect": "Allow",
      "Action": [
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)

# Check if policy already exists
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
if aws iam get-policy --policy-arn "$POLICY_ARN" &> /dev/null; then
    echo -e "${YELLOW}Policy already exists: $POLICY_ARN${NC}"
else
    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document "$POLICY_DOCUMENT" \
        --description "Policy for Terraform Cloud and GitHub Actions to deploy ${PROJECT_NAME} infrastructure" \
        --tags "Key=Project,Value=${PROJECT_NAME}" "Key=ManagedBy,Value=Bootstrap Script"

    echo -e "${GREEN}✓ Policy created: $POLICY_ARN${NC}"
fi

# ============================================================================
# Step 2: Create IAM User
# ============================================================================

echo ""
echo -e "${YELLOW}Step 2: Creating IAM User...${NC}"

if aws iam get-user --user-name "$IAM_USER_NAME" &> /dev/null; then
    echo -e "${YELLOW}User already exists: $IAM_USER_NAME${NC}"
else
    aws iam create-user \
        --user-name "$IAM_USER_NAME" \
        --path "/automation/" \
        --tags "Key=Name,Value=${IAM_USER_NAME}" "Key=Purpose,Value=GitHub Actions and Terraform Cloud" "Key=ManagedBy,Value=Bootstrap Script"

    echo -e "${GREEN}✓ User created: $IAM_USER_NAME${NC}"
fi

# ============================================================================
# Step 3: Attach Policy to User
# ============================================================================

echo ""
echo -e "${YELLOW}Step 3: Attaching Policy to User...${NC}"

aws iam attach-user-policy \
    --user-name "$IAM_USER_NAME" \
    --policy-arn "$POLICY_ARN" || echo -e "${YELLOW}Policy may already be attached${NC}"

echo -e "${GREEN}✓ Policy attached to user${NC}"

# ============================================================================
# Step 4: Create Access Key
# ============================================================================

echo ""
echo -e "${YELLOW}Step 4: Creating Access Key...${NC}"

# Check for existing access keys
EXISTING_KEYS=$(aws iam list-access-keys --user-name "$IAM_USER_NAME" --query 'AccessKeyMetadata[*].AccessKeyId' --output text)

if [ -n "$EXISTING_KEYS" ]; then
    echo -e "${YELLOW}Warning: User already has access keys:${NC}"
    echo "$EXISTING_KEYS"
    echo ""
    read -p "Do you want to create a new access key? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping access key creation"
        echo ""
        echo "======================================================================"
        echo "Setup Complete (No New Access Key Created)"
        echo "======================================================================"
        exit 0
    fi
fi

# Create new access key
ACCESS_KEY_OUTPUT=$(aws iam create-access-key --user-name "$IAM_USER_NAME")

ACCESS_KEY_ID=$(echo "$ACCESS_KEY_OUTPUT" | jq -r '.AccessKey.AccessKeyId')
SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_OUTPUT" | jq -r '.AccessKey.SecretAccessKey')

echo -e "${GREEN}✓ Access key created${NC}"

# ============================================================================
# Output Credentials
# ============================================================================

echo ""
echo "======================================================================"
echo -e "${GREEN}IAM USER CREATED SUCCESSFULLY${NC}"
echo "======================================================================"
echo ""
echo "User Name: $IAM_USER_NAME"
echo "User ARN:  arn:aws:iam::${ACCOUNT_ID}:user/automation/${IAM_USER_NAME}"
echo "Policy:    $POLICY_ARN"
echo ""
echo -e "${RED}IMPORTANT: Save these credentials securely! They won't be shown again.${NC}"
echo ""
echo "Access Key ID:     $ACCESS_KEY_ID"
echo "Secret Access Key: $SECRET_ACCESS_KEY"
echo ""
echo "======================================================================"
echo "Next Steps:"
echo "======================================================================"
echo ""
echo "1. Add to Terraform Cloud workspaces:"
echo "   - Go to workspace → Variables"
echo "   - Add environment variables (mark as sensitive):"
echo "     • AWS_ACCESS_KEY_ID = $ACCESS_KEY_ID"
echo "     • AWS_SECRET_ACCESS_KEY = (the secret key above)"
echo ""
echo "2. Add to GitHub Secrets:"
echo "   - Go to repo → Settings → Secrets and variables → Actions"
echo "   - Add repository secrets:"
echo "     • AWS_ACCESS_KEY_ID = $ACCESS_KEY_ID"
echo "     • AWS_SECRET_ACCESS_KEY = (the secret key above)"
echo ""
echo "3. Store in password manager or secrets vault"
echo ""
echo "======================================================================"
echo ""

# Optionally save to file (encrypted or with warning)
read -p "Do you want to save credentials to a file? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    OUTPUT_FILE="aws-credentials-${IAM_USER_NAME}-$(date +%Y%m%d-%H%M%S).txt"
    cat > "$OUTPUT_FILE" <<EOF
IAM User Credentials
Created: $(date)
==================

User Name: $IAM_USER_NAME
Access Key ID: $ACCESS_KEY_ID
Secret Access Key: $SECRET_ACCESS_KEY

IMPORTANT: Delete this file after saving credentials securely!
EOF
    echo ""
    echo -e "${GREEN}Credentials saved to: $OUTPUT_FILE${NC}"
    echo -e "${RED}WARNING: Delete this file after copying credentials!${NC}"
fi

echo ""
echo -e "${GREEN}Done!${NC}"
