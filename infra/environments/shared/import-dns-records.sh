#!/bin/bash
#
# Script to import existing Cloudflare DNS records into Terraform state
# This resolves the "DNS record already exists" error during deployment
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN}Cloudflare DNS Record Import Script${NC}"
echo -e "${GREEN}==================================================================${NC}"
echo ""

# Check required environment variables
if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo -e "${RED}Error: CLOUDFLARE_API_TOKEN environment variable is not set${NC}"
    echo "Please set it with: export CLOUDFLARE_API_TOKEN='your_token_here'"
    exit 1
fi

ZONE_NAME="roboad.ai"

echo -e "${YELLOW}Step 1: Getting Cloudflare Zone ID for ${ZONE_NAME}...${NC}"

# Get zone ID
ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json")

ZONE_ID=$(echo "$ZONE_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$ZONE_ID" ]; then
    echo -e "${RED}Error: Could not find zone ID for ${ZONE_NAME}${NC}"
    echo "Response: $ZONE_RESPONSE"
    exit 1
fi

echo -e "${GREEN}✓ Found Zone ID: ${ZONE_ID}${NC}"
echo ""

echo -e "${YELLOW}Step 2: Listing DNS records for ACM validation...${NC}"

# Get all DNS records and filter for ACM validation records (CNAME records with _acme-challenge)
DNS_RECORDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=CNAME" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json")

# Extract ACM validation records (they typically contain _acme-challenge or similar AWS validation patterns)
echo "$DNS_RECORDS" | jq -r '.result[] | select(.name | contains("_")) | "\(.id)|\(.name)|\(.content)"' > /tmp/acm_records.txt

if [ ! -s /tmp/acm_records.txt ]; then
    echo -e "${YELLOW}No ACM validation records found. This might be okay if:${NC}"
    echo "  1. The records were already cleaned up"
    echo "  2. They're not yet created"
    echo ""
    echo -e "${YELLOW}All CNAME records in zone:${NC}"
    echo "$DNS_RECORDS" | jq -r '.result[] | "\(.name) -> \(.content)"'
    exit 0
fi

echo -e "${GREEN}Found ACM validation records:${NC}"
cat /tmp/acm_records.txt | while IFS='|' read -r record_id record_name record_content; do
    echo "  - $record_name -> $record_content (ID: $record_id)"
done
echo ""

echo -e "${YELLOW}Step 3: Generating Terraform import commands...${NC}"

# Generate import commands
cat > /tmp/import_commands.sh << 'EOF'
#!/bin/bash
# Generated Terraform import commands for Cloudflare DNS records
# Run this script from the infra/environments/shared directory

set -e

echo "Starting Terraform imports..."
echo ""

EOF

cat /tmp/acm_records.txt | while IFS='|' read -r record_id record_name record_content; do
    # Extract domain name from the full record name (e.g., _abc.roboad.ai -> *.roboad.ai or roboad.ai)
    if [[ "$record_name" == *"roboad.ai" ]]; then
        # Determine the Terraform resource key based on the domain
        # ACM creates validation records for each domain in the certificate
        if [[ "$record_name" == _*".roboad.ai" ]]; then
            # This is for *.roboad.ai (wildcard)
            TF_RESOURCE='cloudflare_record.cert_validation["*.roboad.ai"]'
        else
            # This is for roboad.ai (apex domain)
            TF_RESOURCE='cloudflare_record.cert_validation["roboad.ai"]'
        fi

        echo "terraform import '$TF_RESOURCE' ${ZONE_ID}/${record_id}" >> /tmp/import_commands.sh
        echo -e "${GREEN}  Will import: ${TF_RESOURCE}${NC}"
    fi
done

echo "" >> /tmp/import_commands.sh
echo 'echo ""' >> /tmp/import_commands.sh
echo 'echo "Import completed successfully!"' >> /tmp/import_commands.sh
echo 'echo "You can now run: terraform plan"' >> /tmp/import_commands.sh

chmod +x /tmp/import_commands.sh

echo ""
echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN}Import commands generated!${NC}"
echo -e "${GREEN}==================================================================${NC}"
echo ""
echo "The import script has been saved to: /tmp/import_commands.sh"
echo ""
echo -e "${YELLOW}To import the records into Terraform state:${NC}"
echo "  1. Review the commands: cat /tmp/import_commands.sh"
echo "  2. Run the import: /tmp/import_commands.sh"
echo ""
echo -e "${YELLOW}Or run it directly now:${NC}"
echo "  /tmp/import_commands.sh"
echo ""

# Optionally show the commands
echo -e "${YELLOW}Generated commands:${NC}"
cat /tmp/import_commands.sh
