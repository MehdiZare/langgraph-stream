# Workspace Cleanup Guide

When upgrading Terraform providers (especially major versions), you may encounter state compatibility issues. This guide shows you how to clean up and start fresh.

## Problem

After upgrading Cloudflare provider from v4 to v5, the Terraform state contains old resource types (`cloudflare_record`) that the new provider doesn't recognize (`cloudflare_dns_record`). This causes errors like:

```
Error: no schema available for cloudflare_record.api_pr while reading state
```

## Solution Options

### Option 1: Automated Cleanup Script (Recommended)

Use the provided cleanup script to destroy resources and delete the workspace:

```bash
cd scripts
chmod +x cleanup-pr-workspace.sh

# Set your Terraform Cloud API token
export TF_API_TOKEN='your_token_from_terraform_cloud'

# Cleanup PR #3 workspace
./cleanup-pr-workspace.sh 3
```

The script will:
1. Find the workspace
2. Create a destroy run to remove all AWS resources
3. Wait for completion
4. Delete the Terraform Cloud workspace
5. Next deployment will start with clean state

### Option 2: Manual Cleanup via Terraform Cloud UI

1. **Go to Terraform Cloud**
   - Visit: https://app.terraform.io/app/roboad/workspaces
   - Find workspace: `roboad-fast-ws-pr-3`

2. **Queue Destroy Plan**
   - Click "Settings" → "Destruction and Deletion"
   - Click "Queue destroy plan"
   - Review and confirm the destroy
   - Wait for it to complete

3. **Delete Workspace**
   - After resources are destroyed, go back to "Destruction and Deletion"
   - Click "Delete workspace"
   - Confirm deletion

4. **Trigger New Deployment**
   - Push a new commit or manually trigger the workflow
   - A fresh workspace will be created automatically

### Option 3: State Migration (Advanced)

If you want to keep the workspace and just migrate the state:

```bash
# Get the workspace
terraform workspace select roboad-fast-ws-pr-3

# Migrate each resource (must be done for every cloudflare_record)
terraform state mv 'cloudflare_record.api_pr' 'cloudflare_dns_record.api_pr'

# Verify
terraform state list
```

**Note:** This is complex for workspaces with many resources.

## For Shared Environment

The **shared environment** workspace (`roboad-fast-ws-shared`) also needs migration. You have two options:

### Option A: Clean Start (Safest)

1. **Backup Important Data**
   - ECR repository will be preserved (not managed by Terraform)
   - Secrets in AWS Secrets Manager will be preserved
   - VPC and networking will be recreated (AWS handles gracefully)

2. **Destroy and Recreate**
   ```bash
   export TF_API_TOKEN='your_token'

   # Navigate to shared environment
   cd infra/environments/shared

   # Initialize
   terraform init

   # Destroy (this will remove ACM cert, VPC, etc.)
   terraform destroy

   # Apply fresh
   terraform apply
   ```

3. **ACM Certificate Note**
   - The wildcard SSL certificate will be recreated
   - DNS validation may take 5-30 minutes
   - During this time, PR deployments will fail (expected)

### Option B: Selective State Migration

Migrate only the Cloudflare DNS records:

```bash
cd infra/environments/shared

# For each cert validation record
terraform state mv \
  'cloudflare_record.cert_validation["*.roboad.ai"]' \
  'cloudflare_dns_record.cert_validation["*.roboad.ai"]'

terraform state mv \
  'cloudflare_record.cert_validation["roboad.ai"]' \
  'cloudflare_dns_record.cert_validation["roboad.ai"]'

# Verify
terraform plan  # Should show minimal changes
```

## Production Environment

For production (`roboad-fast-ws-prod`), use **Option B (State Migration)** to avoid downtime:

```bash
cd infra/environments/prod

terraform state mv 'cloudflare_record.api_prod' 'cloudflare_dns_record.api_prod'

terraform plan  # Verify no destructive changes
terraform apply
```

## Verification

After cleanup, verify the next deployment:

1. **Check GitHub Actions**
   - Go to: https://github.com/MehdiZare/langgraph-stream/actions
   - Watch the "Deploy PR Environment" workflow
   - Should complete successfully

2. **Check Terraform Cloud**
   - Workspace should be recreated automatically
   - State should contain `cloudflare_dns_record` resources
   - No errors about missing schemas

3. **Check AWS Resources**
   - ECS service running
   - ALB healthy
   - DNS pointing correctly

## Prevention

To avoid this in the future:

1. **Test major provider upgrades** in PR environments first
2. **Read migration guides** before upgrading providers
3. **Use automated state migration tools** when available
4. **Keep provider versions pinned** until ready to upgrade

## Troubleshooting

### "Workspace is locked"

Wait for current run to complete, or force-cancel it in Terraform Cloud UI.

### "Resources still exist after destroy"

Some resources (like ECR) are preserved intentionally. Manually delete via AWS Console if needed.

### "Cannot delete workspace - state not empty"

Force delete via API:
```bash
curl -X DELETE \
  -H "Authorization: Bearer $TF_API_TOKEN" \
  -H "Content-Type: application/vnd.api+json" \
  "https://app.terraform.io/api/v2/workspaces/<workspace_id>?force=true"
```

## Need Help?

- Terraform Cloud Docs: https://developer.hashicorp.com/terraform/cloud-docs
- Cloudflare Provider v5 Migration: https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/guides/version-5-upgrade
- GitHub Issues: https://github.com/MehdiZare/langgraph-stream/issues
