#!/bin/bash

# Test AWS Credentials
# This script tests if the AWS credentials you plan to use work correctly

echo "Testing AWS Credentials..."
echo ""

# Check if AWS CLI is configured
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed"
    exit 1
fi

echo "Current AWS Identity:"
aws sts get-caller-identity

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ AWS credentials are valid!"
    echo ""
    echo "Now let's get the access keys for Terraform Cloud:"
    echo ""

    # If using the IAM user created by bootstrap
    if aws iam get-user --user-name github-terraform-deployer &> /dev/null; then
        echo "Found IAM user: github-terraform-deployer"
        echo ""
        echo "Access keys for this user:"
        aws iam list-access-keys --user-name github-terraform-deployer
        echo ""
        echo "If you see access keys above, those are what you should add to Terraform Cloud"
        echo ""
        echo "If you need to create new access keys:"
        echo "  cd infra/bootstrap"
        echo "  terraform output access_key_id"
        echo "  terraform output secret_access_key"
    else
        echo "IAM user 'github-terraform-deployer' not found"
        echo ""
        echo "Options:"
        echo "1. Create IAM user with bootstrap:"
        echo "   cd infra/bootstrap && terraform apply"
        echo ""
        echo "2. Or manually create an IAM user and access keys"
    fi
else
    echo "❌ AWS credentials are not valid or not configured"
    echo ""
    echo "Please run: aws configure"
fi
