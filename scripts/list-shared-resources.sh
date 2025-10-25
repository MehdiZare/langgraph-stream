#!/bin/bash
#
# Script to list all AWS resources created by the shared environment
# Use this to verify what needs to be cleaned up
#
# Usage: ./list-shared-resources.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_PREFIX="roboad-backend"

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}Shared Environment Resources Report${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""
echo -e "${YELLOW}Region:${NC} $AWS_REGION"
echo ""

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}AWS credentials not configured${NC}"
    exit 1
fi

echo -e "${GREEN}✓ AWS credentials validated${NC}"
echo ""

# VPC
echo -e "${YELLOW}=== VPC ===${NC}"
aws ec2 describe-vpcs \
    --region "$AWS_REGION" \
    --filters "Name=tag:Project,Values=${PROJECT_PREFIX}" \
    --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}' \
    --output table 2>/dev/null || echo "No VPCs found"
echo ""

# Subnets
echo -e "${YELLOW}=== Subnets ===${NC}"
aws ec2 describe-subnets \
    --region "$AWS_REGION" \
    --filters "Name=tag:Project,Values=${PROJECT_PREFIX}" \
    --query 'Subnets[].{ID:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,Type:Tags[?Key==`Type`].Value|[0]}' \
    --output table 2>/dev/null || echo "No subnets found"
echo ""

# Security Groups
echo -e "${YELLOW}=== Security Groups ===${NC}"
aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --filters "Name=tag:Project,Values=${PROJECT_PREFIX}" \
    --query 'SecurityGroups[].{ID:GroupId,Name:GroupName,Description:Description}' \
    --output table 2>/dev/null || echo "No security groups found"
echo ""

# Internet Gateway
echo -e "${YELLOW}=== Internet Gateways ===${NC}"
aws ec2 describe-internet-gateways \
    --region "$AWS_REGION" \
    --filters "Name=tag:Project,Values=${PROJECT_PREFIX}" \
    --query 'InternetGateways[].{ID:InternetGatewayId,Attachments:Attachments[0].VpcId}' \
    --output table 2>/dev/null || echo "No internet gateways found"
echo ""

# NAT Gateways
echo -e "${YELLOW}=== NAT Gateways ===${NC}"
aws ec2 describe-nat-gateways \
    --region "$AWS_REGION" \
    --filter "Name=tag:Project,Values=${PROJECT_PREFIX}" \
    --query 'NatGateways[].{ID:NatGatewayId,State:State,SubnetId:SubnetId}' \
    --output table 2>/dev/null || echo "No NAT gateways found"
echo ""

# Route Tables
echo -e "${YELLOW}=== Route Tables ===${NC}"
aws ec2 describe-route-tables \
    --region "$AWS_REGION" \
    --filters "Name=tag:Project,Values=${PROJECT_PREFIX}" \
    --query 'RouteTables[].{ID:RouteTableId,Name:Tags[?Key==`Name`].Value|[0]}' \
    --output table 2>/dev/null || echo "No route tables found"
echo ""

# ECR Repository
echo -e "${YELLOW}=== ECR Repositories ===${NC}"
aws ecr describe-repositories \
    --region "$AWS_REGION" \
    --query 'repositories[?contains(repositoryName, `'${PROJECT_PREFIX}'`)].{Name:repositoryName,URI:repositoryUri}' \
    --output table 2>/dev/null || echo "No ECR repositories found"
echo ""

# IAM Roles
echo -e "${YELLOW}=== IAM Roles (ECS) ===${NC}"
aws iam list-roles \
    --query 'Roles[?contains(RoleName, `'${PROJECT_PREFIX}'`)].{Name:RoleName,ARN:Arn}' \
    --output table 2>/dev/null || echo "No IAM roles found"
echo ""

# Secrets Manager
echo -e "${YELLOW}=== Secrets Manager ===${NC}"
aws secretsmanager list-secrets \
    --region "$AWS_REGION" \
    --query 'SecretList[?contains(Name, `'${PROJECT_PREFIX}'`)].{Name:Name,ARN:ARN}' \
    --output table 2>/dev/null || echo "No secrets found"
echo ""

# ACM Certificates
echo -e "${YELLOW}=== ACM Certificates ===${NC}"
aws acm list-certificates \
    --region "$AWS_REGION" \
    --query 'CertificateSummaryList[?DomainName==`*.roboad.ai` || DomainName==`roboad.ai`].{Domain:DomainName,ARN:CertificateArn,Status:Status}' \
    --output table 2>/dev/null || echo "No ACM certificates found"
echo ""

# CloudWatch Log Groups
echo -e "${YELLOW}=== CloudWatch Log Groups ===${NC}"
aws logs describe-log-groups \
    --region "$AWS_REGION" \
    --log-group-name-prefix "/ecs/${PROJECT_PREFIX}" \
    --query 'logGroups[].{Name:logGroupName,RetentionDays:retentionInDays}' \
    --output table 2>/dev/null || echo "No log groups found"
echo ""

# S3 Buckets
echo -e "${YELLOW}=== S3 Buckets ===${NC}"
aws s3api list-buckets \
    --query 'Buckets[?contains(Name, `'${PROJECT_PREFIX}'`) || contains(Name, `roboad`)].{Name:Name,CreationDate:CreationDate}' \
    --output table 2>/dev/null || echo "No S3 buckets found"
echo ""

# ECS Cluster
echo -e "${YELLOW}=== ECS Clusters ===${NC}"
aws ecs list-clusters \
    --region "$AWS_REGION" \
    --query 'clusterArns[?contains(@, `'${PROJECT_PREFIX}'`)]' \
    --output table 2>/dev/null || echo "No ECS clusters found"
echo ""

echo -e "${BLUE}=================================================================${NC}"
echo -e "${GREEN}Resource listing complete${NC}"
echo -e "${BLUE}=================================================================${NC}"
