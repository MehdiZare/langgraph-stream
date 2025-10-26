#!/bin/bash
#
# Script to cleanup and destroy a PR environment workspace
# This is useful when you need to start fresh with a clean state
#
# Usage: ./cleanup-pr-workspace.sh <PR_NUMBER>
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -ne 1 ]; then
    echo -e "${RED}Usage: $0 <PR_NUMBER>${NC}"
    echo "Example: $0 3"
    exit 1
fi

PR_NUMBER=$1
TF_CLOUD_ORGANIZATION="roboad"
TF_WORKSPACE_PREFIX="roboad-fast-ws-pr"
WORKSPACE_NAME="${TF_WORKSPACE_PREFIX}-${PR_NUMBER}"

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}PR Environment Cleanup Script${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""
echo -e "${YELLOW}PR Number:${NC} $PR_NUMBER"
echo -e "${YELLOW}Workspace:${NC} $WORKSPACE_NAME"
echo ""

# Check required environment variables
if [ -z "$TF_API_TOKEN" ]; then
    echo -e "${RED}Error: TF_API_TOKEN environment variable is not set${NC}"
    echo "Please set it with: export TF_API_TOKEN='your_token_here'"
    echo "Get your token from: https://app.terraform.io/app/settings/tokens"
    exit 1
fi

echo -e "${YELLOW}Step 1: Checking if workspace exists...${NC}"

# Get workspace ID
WORKSPACE_ID=$(curl -s \
  --header "Authorization: Bearer $TF_API_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  "https://app.terraform.io/api/v2/organizations/$TF_CLOUD_ORGANIZATION/workspaces/$WORKSPACE_NAME" \
  | jq -r '.data.id // empty')

if [ -z "$WORKSPACE_ID" ]; then
    echo -e "${YELLOW}Workspace $WORKSPACE_NAME does not exist. Nothing to clean up.${NC}"
    exit 0
fi

echo -e "${GREEN}✓ Workspace exists (ID: $WORKSPACE_ID)${NC}"
echo ""

echo -e "${YELLOW}Step 2: Creating destroy run to remove all resources...${NC}"

# Create a destroy run
DESTROY_RUN=$(curl -s \
  --header "Authorization: Bearer $TF_API_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --request POST \
  --data @- \
  "https://app.terraform.io/api/v2/runs" <<EOF
{
  "data": {
    "type": "runs",
    "attributes": {
      "is-destroy": true,
      "message": "Destroy PR #${PR_NUMBER} resources for clean restart",
      "auto-apply": true
    },
    "relationships": {
      "workspace": {
        "data": {
          "type": "workspaces",
          "id": "$WORKSPACE_ID"
        }
      }
    }
  }
}
EOF
)

RUN_ID=$(echo "$DESTROY_RUN" | jq -r '.data.id // empty')

if [ -z "$RUN_ID" ]; then
    echo -e "${RED}Failed to create destroy run${NC}"
    echo "$DESTROY_RUN" | jq .
    exit 1
fi

echo -e "${GREEN}✓ Destroy run created (ID: $RUN_ID)${NC}"
echo ""

echo -e "${YELLOW}Step 3: Monitoring destroy run...${NC}"
echo "View run at: https://app.terraform.io/app/$TF_CLOUD_ORGANIZATION/workspaces/$WORKSPACE_NAME/runs/$RUN_ID"
echo ""

# Poll for run status
MAX_WAIT=600  # 10 minutes
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    RUN_STATUS=$(curl -s \
      --header "Authorization: Bearer $TF_API_TOKEN" \
      --header "Content-Type: application/vnd.api+json" \
      "https://app.terraform.io/api/v2/runs/$RUN_ID" \
      | jq -r '.data.attributes.status')

    case "$RUN_STATUS" in
        "applied")
            echo -e "${GREEN}✓ Resources destroyed successfully${NC}"
            break
            ;;
        "errored"|"canceled"|"force_canceled")
            echo -e "${RED}✗ Destroy run failed with status: $RUN_STATUS${NC}"
            echo "Check the run logs at the URL above"
            exit 1
            ;;
        *)
            echo -ne "${YELLOW}Status: $RUN_STATUS... (${ELAPSED}s)${NC}\r"
            sleep 5
            ELAPSED=$((ELAPSED + 5))
            ;;
    esac
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}✗ Timeout waiting for destroy run to complete${NC}"
    echo "Check the run logs at the URL above"
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 4: Deleting workspace...${NC}"

# Delete the workspace
DELETE_RESPONSE=$(curl -s -w "\n%{http_code}" \
  --header "Authorization: Bearer $TF_API_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --request DELETE \
  "https://app.terraform.io/api/v2/workspaces/$WORKSPACE_ID")

HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -n1)

if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Workspace deleted successfully${NC}"
else
    echo -e "${RED}✗ Failed to delete workspace (HTTP $HTTP_CODE)${NC}"
    echo "$DELETE_RESPONSE" | head -n-1
    exit 1
fi

echo ""
echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo ""
echo "The PR #$PR_NUMBER workspace has been destroyed and deleted."
echo "The next deployment will start with a clean state."
echo ""
echo "Resources that were cleaned up:"
echo "  - ECS Service and Task Definition"
echo "  - Application Load Balancer"
echo "  - Target Groups and Listeners"
echo "  - Security Groups"
echo "  - CloudWatch Log Streams"
echo "  - Cloudflare DNS Records"
echo "  - Terraform Cloud Workspace"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Push a new commit to trigger a fresh deployment"
echo "  2. Or manually trigger the 'Deploy PR Environment' workflow"
echo ""
