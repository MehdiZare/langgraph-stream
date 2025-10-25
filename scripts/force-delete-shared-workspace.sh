#!/bin/bash
#
# Script to force-delete the shared workspace from Terraform Cloud
# This bypasses state checks and deletes the workspace even if state is corrupted
#
# WARNING: This does NOT destroy AWS resources!
# You must manually clean up AWS resources first or they will be orphaned
#
# Usage: ./force-delete-shared-workspace.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TF_CLOUD_ORGANIZATION="roboad"
WORKSPACE_NAME="roboad-fast-ws-shared"

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}Force Delete Shared Workspace${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""
echo -e "${YELLOW}Workspace:${NC} $WORKSPACE_NAME"
echo ""
echo -e "${RED}⚠️  WARNING ⚠️${NC}"
echo -e "${RED}This will FORCE DELETE the workspace without destroying resources!${NC}"
echo -e "${RED}Make sure you've cleaned up AWS resources first or they will be orphaned!${NC}"
echo ""
echo -e "${YELLOW}Recommended steps BEFORE running this:${NC}"
echo "1. Run ./list-shared-resources.sh to see what exists"
echo "2. Manually delete AWS resources via Console or cleanup script"
echo "3. Then run this script to delete the workspace"
echo ""
read -p "Have you cleaned up AWS resources? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Aborted. Please clean up AWS resources first.${NC}"
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
echo -e "${YELLOW}Step 1: Finding workspace...${NC}"

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
echo -e "${YELLOW}Step 2: Checking if workspace is locked...${NC}"

# Check workspace lock status
LOCK_STATUS=$(curl -s \
  --header "Authorization: Bearer $TF_API_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  "https://app.terraform.io/api/v2/workspaces/${WORKSPACE_ID}" \
  | jq -r '.data.attributes.locked // empty')

if [ "$LOCK_STATUS" = "true" ]; then
    echo -e "${YELLOW}Workspace is locked. Attempting to unlock...${NC}"

    # Unlock workspace
    UNLOCK_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/unlock_response.json \
      --header "Authorization: Bearer $TF_API_TOKEN" \
      --header "Content-Type: application/vnd.api+json" \
      --request POST \
      "https://app.terraform.io/api/v2/workspaces/${WORKSPACE_ID}/actions/unlock")

    HTTP_CODE="${UNLOCK_RESPONSE: -3}"

    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✓ Workspace unlocked${NC}"
    else
        echo -e "${YELLOW}⚠ Could not unlock (HTTP ${HTTP_CODE}), continuing anyway...${NC}"
    fi
else
    echo -e "${GREEN}✓ Workspace is not locked${NC}"
fi

echo ""
echo -e "${YELLOW}Step 3: Force deleting workspace...${NC}"
echo -e "${BLUE}This will permanently delete all workspace data:${NC}"
echo "  - State history"
echo "  - Run history  "
echo "  - Variables"
echo "  - Settings"
echo ""
read -p "Are you absolutely sure? (yes/no): " FINAL_CONFIRM

if [ "$FINAL_CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 0
fi

# Force delete workspace
DELETE_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/delete_response.json \
  --header "Authorization: Bearer $TF_API_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --request DELETE \
  "https://app.terraform.io/api/v2/workspaces/${WORKSPACE_ID}")

HTTP_CODE="${DELETE_RESPONSE: -3}"

if [ "$HTTP_CODE" = "204" ]; then
    echo -e "${GREEN}✓ Workspace deleted successfully${NC}"
else
    echo -e "${RED}Error: Failed to delete workspace (HTTP ${HTTP_CODE})${NC}"
    cat /tmp/delete_response.json | jq . 2>/dev/null || cat /tmp/delete_response.json
    exit 1
fi

echo ""
echo -e "${BLUE}=================================================================${NC}"
echo -e "${GREEN}✓ Force Delete Complete!${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Verify AWS resources are deleted (or will be manually managed)"
echo "2. Push a commit to trigger new deployment"
echo "3. Terraform Cloud will create a fresh workspace automatically"
echo "4. The new workspace will have clean v5-compatible state"
echo ""
echo -e "${YELLOW}Note:${NC} If you haven't cleaned up AWS resources, they are now orphaned!"
echo "You'll need to manually delete them via AWS Console to avoid costs."
echo ""
