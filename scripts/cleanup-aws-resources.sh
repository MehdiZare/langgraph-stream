#!/bin/bash
#
# Script to cleanup orphaned AWS resources for a PR environment
# Use this when Terraform workspace was deleted but AWS resources still exist
#
# Usage: ./cleanup-aws-resources.sh <PR_NUMBER>
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ $# -ne 1 ]; then
    echo -e "${RED}Usage: $0 <PR_NUMBER>${NC}"
    exit 1
fi

PR_NUMBER=$1
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_PREFIX="roboad-backend"
PR_PREFIX="${PROJECT_PREFIX}-pr-${PR_NUMBER}"

echo -e "${YELLOW}Cleaning up AWS resources for PR #${PR_NUMBER}...${NC}"
echo ""

# Function to check if AWS credentials are configured
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}AWS credentials not configured or expired${NC}"
        echo "Please configure AWS credentials first"
        exit 1
    fi
    echo -e "${GREEN}✓ AWS credentials validated${NC}"
}

# Cleanup security groups
cleanup_security_groups() {
    echo -e "${YELLOW}Cleaning up security groups...${NC}"

    # Get security group IDs
    SG_IDS=$(aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --filters "Name=group-name,Values=${PR_PREFIX}-*" \
        --query "SecurityGroups[].GroupId" \
        --output text 2>/dev/null || true)

    if [ -z "$SG_IDS" ]; then
        echo "  No security groups found"
        return
    fi

    for SG_ID in $SG_IDS; do
        echo "  Deleting security group: $SG_ID"
        aws ec2 delete-security-group \
            --region "$AWS_REGION" \
            --group-id "$SG_ID" 2>/dev/null || echo "    Failed (may have dependencies)"
    done
}

# Cleanup load balancer
cleanup_load_balancer() {
    echo -e "${YELLOW}Cleaning up load balancer...${NC}"

    ALB_ARN=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --query "LoadBalancers[?LoadBalancerName=='${PR_PREFIX}-alb'].LoadBalancerArn" \
        --output text 2>/dev/null || true)

    if [ -z "$ALB_ARN" ]; then
        echo "  No load balancer found"
        return
    fi

    echo "  Deleting load balancer: ${PR_PREFIX}-alb"
    aws elbv2 delete-load-balancer \
        --region "$AWS_REGION" \
        --load-balancer-arn "$ALB_ARN" 2>/dev/null || echo "    Failed"

    echo "  Waiting for load balancer to be deleted..."
    aws elbv2 wait load-balancers-deleted \
        --region "$AWS_REGION" \
        --load-balancer-arns "$ALB_ARN" 2>/dev/null || true
}

# Cleanup target groups
cleanup_target_groups() {
    echo -e "${YELLOW}Cleaning up target groups...${NC}"

    TG_ARNS=$(aws elbv2 describe-target-groups \
        --region "$AWS_REGION" \
        --query "TargetGroups[?TargetGroupName=='${PR_PREFIX}-tg'].TargetGroupArn" \
        --output text 2>/dev/null || true)

    if [ -z "$TG_ARNS" ]; then
        echo "  No target groups found"
        return
    fi

    for TG_ARN in $TG_ARNS; do
        echo "  Deleting target group: ${PR_PREFIX}-tg"
        aws elbv2 delete-target-group \
            --region "$AWS_REGION" \
            --target-group-arn "$TG_ARN" 2>/dev/null || echo "    Failed"
    done
}

# Cleanup ECS service
cleanup_ecs_service() {
    echo -e "${YELLOW}Cleaning up ECS service...${NC}"

    CLUSTER_NAME="${PROJECT_PREFIX}-cluster"
    SERVICE_NAME="${PR_PREFIX}-service"

    # Check if service exists
    SERVICE_EXISTS=$(aws ecs describe-services \
        --region "$AWS_REGION" \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --query "services[?status=='ACTIVE'].serviceName" \
        --output text 2>/dev/null || true)

    if [ -z "$SERVICE_EXISTS" ]; then
        echo "  No ECS service found"
    else
        echo "  Updating service to 0 desired count..."
        aws ecs update-service \
            --region "$AWS_REGION" \
            --cluster "$CLUSTER_NAME" \
            --service "$SERVICE_NAME" \
            --desired-count 0 &>/dev/null || true

        echo "  Deleting ECS service..."
        aws ecs delete-service \
            --region "$AWS_REGION" \
            --cluster "$CLUSTER_NAME" \
            --service "$SERVICE_NAME" \
            --force &>/dev/null || true
    fi
}

# Cleanup CloudWatch log groups
cleanup_cloudwatch_logs() {
    echo -e "${YELLOW}Cleaning up CloudWatch log groups...${NC}"

    LOG_GROUP="/ecs/${PR_PREFIX}"

    if aws logs describe-log-groups --region "$AWS_REGION" --log-group-name-prefix "$LOG_GROUP" --query "logGroups[].logGroupName" --output text 2>/dev/null | grep -q "$LOG_GROUP"; then
        echo "  Deleting log group: $LOG_GROUP"
        aws logs delete-log-group \
            --region "$AWS_REGION" \
            --log-group-name "$LOG_GROUP" 2>/dev/null || echo "    Failed"
    else
        echo "  No log groups found"
    fi
}

# Main cleanup flow
check_aws_credentials
echo ""

cleanup_ecs_service
cleanup_load_balancer
cleanup_target_groups
cleanup_security_groups
cleanup_cloudwatch_logs

echo ""
echo -e "${GREEN}AWS resource cleanup complete!${NC}"
echo ""
echo -e "${YELLOW}Note:${NC} Some resources may have failed to delete due to dependencies."
echo "Run the script again after a few minutes if needed."
echo ""
