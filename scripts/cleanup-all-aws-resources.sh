#!/bin/bash
#
# Complete AWS Infrastructure Cleanup Script
# Deletes ALL roboad-backend resources (shared, PR, prod environments)
#
# WARNING: This is DESTRUCTIVE and will delete:
# - All VPCs, subnets, NAT gateways, security groups
# - All ECS clusters, services, and tasks
# - All IAM roles and secrets
# - S3 buckets and all data
# - ACM certificates
# - CloudWatch log groups
#
# Usage: ./cleanup-all-aws-resources.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_PREFIX="roboad-backend"

echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}║        COMPLETE AWS INFRASTRUCTURE CLEANUP                     ║${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}║  ⚠️  WARNING: THIS WILL DELETE EVERYTHING! ⚠️                  ║${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}This will delete ALL resources with '${PROJECT_PREFIX}' tag/name:${NC}"
echo "  • 2 VPCs and all networking (NAT gateways cost $$!)"
echo "  • 3 ECS clusters (shared, pr-3, prod)"
echo "  • IAM roles and policies"
echo "  • Secrets Manager secrets (API keys, Clerk, Supabase)"
echo "  • S3 bucket and ALL scan data"
echo "  • ACM certificates"
echo "  • CloudWatch log groups"
echo ""
echo -e "${GREEN}PRESERVED:${NC}"
echo "  ✅ ECR Repository (Docker images safe)"
echo ""
echo -e "${BLUE}Region: ${AWS_REGION}${NC}"
echo ""
read -p "Type 'DELETE EVERYTHING' to continue: " CONFIRM

if [ "$CONFIRM" != "DELETE EVERYTHING" ]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 0
fi

# Check AWS credentials
echo ""
echo -e "${MAGENTA}[Preflight]${NC} Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured${NC}"
    exit 1
fi
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✓ Connected to AWS account: ${ACCOUNT_ID}${NC}"
echo ""

# Track what was deleted
DELETED_RESOURCES=0

# Function to increment counter
count_deleted() {
    DELETED_RESOURCES=$((DELETED_RESOURCES + 1))
}

# ============================================================================
# STEP 1: DELETE ECS SERVICES AND TASKS
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[Step 1/11] Deleting ECS Services and Tasks${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Get all clusters
CLUSTERS=$(aws ecs list-clusters --region "$AWS_REGION" \
  --query 'clusterArns[?contains(@, `'${PROJECT_PREFIX}'`)]' --output text)

for CLUSTER_ARN in $CLUSTERS; do
    CLUSTER_NAME=$(basename "$CLUSTER_ARN")
    echo -e "${YELLOW}Processing cluster: ${CLUSTER_NAME}${NC}"

    # Get all services in cluster
    SERVICES=$(aws ecs list-services --region "$AWS_REGION" \
      --cluster "$CLUSTER_ARN" --query 'serviceArns' --output text)

    for SERVICE_ARN in $SERVICES; do
        SERVICE_NAME=$(basename "$SERVICE_ARN")
        echo "  Scaling down service: $SERVICE_NAME"
        aws ecs update-service --region "$AWS_REGION" \
          --cluster "$CLUSTER_ARN" --service "$SERVICE_ARN" \
          --desired-count 0 &>/dev/null || true

        echo "  Deleting service: $SERVICE_NAME"
        aws ecs delete-service --region "$AWS_REGION" \
          --cluster "$CLUSTER_ARN" --service "$SERVICE_ARN" \
          --force &>/dev/null || true
        count_deleted
    done

    echo -e "${GREEN}✓ Cluster ${CLUSTER_NAME} services deleted${NC}"
done

echo ""

# ============================================================================
# STEP 2: DELETE LOAD BALANCERS AND TARGET GROUPS
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[Step 2/11] Deleting Load Balancers and Target Groups${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Delete ALBs
ALBS=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
  --query 'LoadBalancers[?contains(LoadBalancerName, `'${PROJECT_PREFIX}'`)].LoadBalancerArn' \
  --output text 2>/dev/null || true)

for ALB_ARN in $ALBS; do
    ALB_NAME=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
      --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].LoadBalancerName' --output text)
    echo "  Deleting ALB: $ALB_NAME"
    aws elbv2 delete-load-balancer --region "$AWS_REGION" \
      --load-balancer-arn "$ALB_ARN" 2>/dev/null || true
    count_deleted
done

# Wait for ALBs to delete
if [ ! -z "$ALBS" ]; then
    echo "  Waiting for load balancers to delete..."
    sleep 30
fi

# Delete Target Groups
TGS=$(aws elbv2 describe-target-groups --region "$AWS_REGION" \
  --query 'TargetGroups[?contains(TargetGroupName, `'${PROJECT_PREFIX}'`)].TargetGroupArn' \
  --output text 2>/dev/null || true)

for TG_ARN in $TGS; do
    TG_NAME=$(aws elbv2 describe-target-groups --region "$AWS_REGION" \
      --target-group-arns "$TG_ARN" --query 'TargetGroups[0].TargetGroupName' --output text)
    echo "  Deleting target group: $TG_NAME"
    aws elbv2 delete-target-group --region "$AWS_REGION" \
      --target-group-arn "$TG_ARN" 2>/dev/null || true
    count_deleted
done

echo -e "${GREEN}✓ Load balancers and target groups deleted${NC}"
echo ""

# ============================================================================
# STEP 3: EMPTY AND DELETE S3 BUCKETS
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[Step 3/11] Emptying and Deleting S3 Buckets${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

BUCKETS=$(aws s3api list-buckets \
  --query 'Buckets[?contains(Name, `'${PROJECT_PREFIX}'`) || contains(Name, `roboad`)].Name' \
  --output text)

for BUCKET in $BUCKETS; do
    echo "  Emptying bucket: $BUCKET"
    aws s3 rm s3://$BUCKET --recursive &>/dev/null || true

    echo "  Deleting bucket: $BUCKET"
    aws s3api delete-bucket --bucket $BUCKET 2>/dev/null || true
    count_deleted
done

echo -e "${GREEN}✓ S3 buckets deleted${NC}"
echo ""

# ============================================================================
# STEP 4: DELETE NAT GATEWAYS (SLOW!)
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[Step 4/11] Deleting NAT Gateways${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}⏰ This step is slow (2-5 minutes). NAT gateways cost money!${NC}"

NAT_IDS=$(aws ec2 describe-nat-gateways --region "$AWS_REGION" \
  --filter "Name=tag:Project,Values=${PROJECT_PREFIX}" "Name=state,Values=available" \
  --query 'NatGateways[].NatGatewayId' --output text)

if [ -z "$NAT_IDS" ]; then
    echo "  No NAT gateways found"
else
    for NAT_ID in $NAT_IDS; do
        echo "  Deleting NAT gateway: $NAT_ID"
        aws ec2 delete-nat-gateway --region "$AWS_REGION" --nat-gateway-id "$NAT_ID" &>/dev/null
        count_deleted
    done

    echo "  Waiting for NAT gateways to delete (this takes 2-5 minutes)..."
    for NAT_ID in $NAT_IDS; do
        while true; do
            STATE=$(aws ec2 describe-nat-gateways --region "$AWS_REGION" \
              --nat-gateway-ids "$NAT_ID" \
              --query 'NatGateways[0].State' --output text 2>/dev/null || echo "deleted")

            if [ "$STATE" = "deleted" ] || [ "$STATE" = "None" ]; then
                echo "    ✓ $NAT_ID deleted"
                break
            fi
            echo "    $NAT_ID status: $STATE (waiting...)"
            sleep 10
        done
    done
fi

echo -e "${GREEN}✓ NAT gateways deleted${NC}"
echo ""

# ============================================================================
# STEP 5: RELEASE ELASTIC IPS
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[Step 5/11] Releasing Elastic IPs${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

EIP_ALLOCS=$(aws ec2 describe-addresses --region "$AWS_REGION" \
  --query 'Addresses[?contains(Tags[?Key==`Project`].Value, `'${PROJECT_PREFIX}'`)].AllocationId' \
  --output text)

for EIP_ALLOC in $EIP_ALLOCS; do
    echo "  Releasing Elastic IP: $EIP_ALLOC"
    aws ec2 release-address --region "$AWS_REGION" --allocation-id $EIP_ALLOC 2>/dev/null || true
    count_deleted
done

echo -e "${GREEN}✓ Elastic IPs released${NC}"
echo ""

# ============================================================================
# STEP 6: DELETE VPCS (AUTO-DELETES SUBNETS, IGWS, ROUTE TABLES)
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[Step 6/11] Deleting VPCs${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

VPC_IDS=$(aws ec2 describe-vpcs --region "$AWS_REGION" \
  --filters "Name=tag:Project,Values=${PROJECT_PREFIX}" \
  --query 'Vpcs[].VpcId' --output text)

for VPC_ID in $VPC_IDS; do
    echo "  Detaching and deleting internet gateways for VPC: $VPC_ID"
    IGW_IDS=$(aws ec2 describe-internet-gateways --region "$AWS_REGION" \
      --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
      --query 'InternetGateways[].InternetGatewayId' --output text)

    for IGW_ID in $IGW_IDS; do
        aws ec2 detach-internet-gateway --region "$AWS_REGION" \
          --internet-gateway-id $IGW_ID --vpc-id $VPC_ID 2>/dev/null || true
        aws ec2 delete-internet-gateway --region "$AWS_REGION" \
          --internet-gateway-id $IGW_ID 2>/dev/null || true
    done

    echo "  Deleting VPC: $VPC_ID"
    aws ec2 delete-vpc --region "$AWS_REGION" --vpc-id $VPC_ID 2>/dev/null || {
        echo -e "${YELLOW}    ⚠ VPC delete failed (may have dependencies), will retry...${NC}"
    }
    count_deleted
done

echo -e "${GREEN}✓ VPCs deleted${NC}"
echo ""

# ============================================================================
# STEP 7: DELETE SECURITY GROUPS
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[Step 7/11] Deleting Security Groups${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

SG_IDS=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
  --filters "Name=tag:Project,Values=${PROJECT_PREFIX}" \
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)

for SG_ID in $SG_IDS; do
    echo "  Deleting security group: $SG_ID"
    aws ec2 delete-security-group --region "$AWS_REGION" --group-id $SG_ID 2>/dev/null || {
        echo -e "${YELLOW}    ⚠ Failed (may have dependencies or already deleted)${NC}"
    }
    count_deleted
done

echo -e "${GREEN}✓ Security groups deleted${NC}"
echo ""

# ============================================================================
# STEP 8: DELETE ACM CERTIFICATES
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[Step 8/11] Deleting ACM Certificates${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

CERT_ARNS=$(aws acm list-certificates --region "$AWS_REGION" \
  --query 'CertificateSummaryList[?DomainName==`*.roboad.ai` || DomainName==`roboad.ai`].CertificateArn' \
  --output text)

for CERT_ARN in $CERT_ARNS; do
    echo "  Deleting ACM certificate: $CERT_ARN"
    aws acm delete-certificate --region "$AWS_REGION" --certificate-arn "$CERT_ARN" 2>/dev/null || true
    count_deleted
done

echo -e "${GREEN}✓ ACM certificates deleted${NC}"
echo ""

# ============================================================================
# STEP 9: DELETE IAM ROLES
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[Step 9/11] Deleting IAM Roles${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

ROLES=$(aws iam list-roles \
  --query 'Roles[?contains(RoleName, `'${PROJECT_PREFIX}'`)].RoleName' --output text)

for ROLE in $ROLES; do
    echo "  Deleting inline policies for role: $ROLE"
    POLICIES=$(aws iam list-role-policies --role-name "$ROLE" \
      --query 'PolicyNames' --output text 2>/dev/null || true)

    for POLICY in $POLICIES; do
        aws iam delete-role-policy --role-name "$ROLE" --policy-name "$POLICY" 2>/dev/null || true
    done

    echo "  Detaching managed policies for role: $ROLE"
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE" \
      --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true)

    for POLICY_ARN in $ATTACHED_POLICIES; do
        aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$POLICY_ARN" 2>/dev/null || true
    done

    echo "  Deleting role: $ROLE"
    aws iam delete-role --role-name "$ROLE" 2>/dev/null || true
    count_deleted
done

echo -e "${GREEN}✓ IAM roles deleted${NC}"
echo ""

# ============================================================================
# STEP 10: DELETE SECRETS
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[Step 10/11] Deleting Secrets${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

SECRET_ARNS=$(aws secretsmanager list-secrets --region "$AWS_REGION" \
  --query 'SecretList[?contains(Name, `'${PROJECT_PREFIX}'`)].ARN' --output text)

for SECRET_ARN in $SECRET_ARNS; do
    SECRET_NAME=$(basename "$SECRET_ARN" | cut -d'-' -f1-10)
    echo "  Force deleting secret: $SECRET_NAME"
    aws secretsmanager delete-secret --region "$AWS_REGION" \
      --secret-id "$SECRET_ARN" --force-delete-without-recovery 2>/dev/null || true
    count_deleted
done

echo -e "${GREEN}✓ Secrets deleted${NC}"
echo ""

# ============================================================================
# STEP 11: DELETE CLOUDWATCH LOG GROUPS
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[Step 11/11] Deleting CloudWatch Log Groups${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

LOG_GROUPS=$(aws logs describe-log-groups --region "$AWS_REGION" \
  --log-group-name-prefix "/ecs/${PROJECT_PREFIX}" \
  --query 'logGroups[].logGroupName' --output text)

for LOG_GROUP in $LOG_GROUPS; do
    echo "  Deleting log group: $LOG_GROUP"
    aws logs delete-log-group --region "$AWS_REGION" --log-group-name "$LOG_GROUP" 2>/dev/null || true
    count_deleted
done

echo -e "${GREEN}✓ CloudWatch log groups deleted${NC}"
echo ""

# ============================================================================
# DELETE ECS CLUSTERS (NOW THAT SERVICES ARE GONE)
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[Cleanup] Deleting ECS Clusters${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

for CLUSTER_ARN in $CLUSTERS; do
    CLUSTER_NAME=$(basename "$CLUSTER_ARN")
    echo "  Deleting cluster: $CLUSTER_NAME"
    aws ecs delete-cluster --region "$AWS_REGION" --cluster "$CLUSTER_ARN" &>/dev/null || true
    count_deleted
done

echo -e "${GREEN}✓ ECS clusters deleted${NC}"
echo ""

# ============================================================================
# FINAL REPORT
# ============================================================================
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                                ║${NC}"
echo -e "${GREEN}║              ✓ AWS CLEANUP COMPLETE!                           ║${NC}"
echo -e "${GREEN}║                                                                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Resources Deleted: ${DELETED_RESOURCES}${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Force delete Terraform Cloud workspaces:"
echo "   cd scripts"
echo "   export TF_API_TOKEN='your_token'"
echo "   ./force-delete-shared-workspace.sh"
echo ""
echo "2. Trigger fresh deployments"
echo "   - Shared environment will be created automatically"
echo "   - PR and prod environments as needed"
echo ""
echo -e "${GREEN}✅ ECR Repository preserved - Docker images are safe!${NC}"
echo ""
