#!/bin/bash
#
# Script to cleanup and destroy the shared environment workspace
# Use this when the workspace has corrupted state and needs to start fresh
#
# Usage: ./cleanup-shared-workspace.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TF_CLOUD_ORGANIZATION="roboad"
WORKSPACE_NAME="roboad-fast-ws-shared"

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}Shared Environment Workspace Cleanup Script${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""
echo -e "${YELLOW}Workspace:${NC} $WORKSPACE_NAME"
echo ""
echo -e "${RED}WARNING: This will destroy all shared infrastructure!${NC}"
echo -e "${RED}This includes: VPC, ECR, IAM roles, Secrets, ACM cert${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 0
fi

# Check required environment variables
if [ -z "$TF_API_TOKEN" ]; then
    echo -e "${RED}Error: TF_API_TOKEN environment variable is not set${NC}"
    echo "Please set it with: export TF_API_TOKEN='your_token_here'"
    echo "Get your token from: https://app.terraform.io/app/settings/tokens"
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 1: Checking if workspace exists...${NC}"

# Get workspace ID
WORKSPACE_ID=$(curl -s \
  --header "Authorization: Bearer $TF_API_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  "https://app.terraform.io/api/v2/organizations/${TF_CLOUD_ORGANIZATION}/workspaces/${WORKSPACE_NAME}" \
  | jq -r '.data.id // empty')

if [ -z "$WORKSPACE_ID" ]; then
    echo -e "${RED}Error: Workspace '${WORKSPACE_NAME}' not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found workspace: ${WORKSPACE_ID}${NC}"

echo ""
echo -e "${YELLOW}Step 2: Creating destroy run...${NC}"

# Create destroy run
RUN_RESPONSE=$(curl -s \
  --header "Authorization: Bearer $TF_API_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --request POST \
  --data @- \
  "https://app.terraform.io/api/v2/runs" <<EOF
{
  "data": {
    "attributes": {
      "is-destroy": true,
      "message": "Destroy run to clean up corrupted state"
    },
    "relationships": {
      "workspace": {
        "data": {
          "type": "workspaces",
          "id": "$WORKSPACE_ID"
        }
      }
    },
    "type": "runs"
  }
}
EOF
)

RUN_ID=$(echo "$RUN_RESPONSE" | jq -r '.data.id // empty')

if [ -z "$RUN_ID" ]; then
    echo -e "${RED}Error: Failed to create destroy run${NC}"
    echo "$RUN_RESPONSE" | jq .
    exit 1
fi

echo -e "${GREEN}✓ Created destroy run: ${RUN_ID}${NC}"
echo -e "${BLUE}View in Terraform Cloud: https://app.terraform.io/app/${TF_CLOUD_ORGANIZATION}/workspaces/${WORKSPACE_NAME}/runs/${RUN_ID}${NC}"

echo ""
echo -e "${YELLOW}Step 3: Waiting for run to complete...${NC}"
echo -e "${BLUE}(This may take a few minutes)${NC}"

# Poll run status
while true; do
    RUN_STATUS=$(curl -s \
      --header "Authorization: Bearer $TF_API_TOKEN" \
      --header "Content-Type: application/vnd.api+json" \
      "https://app.terraform.io/api/v2/runs/${RUN_ID}" \
      | jq -r '.data.attributes.status // empty')

    case "$RUN_STATUS" in
        "planned")
            echo -e "${YELLOW}  Plan complete, waiting for confirmation...${NC}"
            echo -e "${BLUE}  Please confirm the destroy in Terraform Cloud UI${NC}"
            ;;
        "policy_checked"|"policy_override")
            echo -e "${YELLOW}  Policy check complete, waiting for apply...${NC}"
            ;;
        "applying")
            echo -e "${YELLOW}  Destroying resources...${NC}"
            ;;
        "applied")
            echo -e "${GREEN}✓ Destroy completed successfully${NC}"
            break
            ;;
        "errored"|"discarded"|"canceled")
            echo -e "${RED}Error: Run ${RUN_STATUS}${NC}"
            echo -e "${RED}Check Terraform Cloud for details${NC}"
            exit 1
            ;;
        *)
            echo -e "${BLUE}  Current status: ${RUN_STATUS}${NC}"
            ;;
    esac

    sleep 10
done

echo ""
echo -e "${YELLOW}Step 4: Deleting workspace...${NC}"

# Delete workspace
DELETE_RESPONSE=$(curl -s -w "%{http_code}" \
  --header "Authorization: Bearer $TF_API_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --request DELETE \
  "https://app.terraform.io/api/v2/workspaces/${WORKSPACE_ID}")

HTTP_CODE="${DELETE_RESPONSE: -3}"

if [ "$HTTP_CODE" = "204" ]; then
    echo -e "${GREEN}✓ Workspace deleted successfully${NC}"
else
    echo -e "${RED}Error: Failed to delete workspace (HTTP ${HTTP_CODE})${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}=================================================================${NC}"
echo -e "${GREEN}✓ Cleanup Complete!${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Push your updated Terraform code"
echo "2. Terraform Cloud will automatically create a new workspace"
echo "3. The workspace will deploy with clean state"
echo ""
