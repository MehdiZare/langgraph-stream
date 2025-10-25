# Fixing Cloudflare DNS Record Conflict

## Problem

The Terraform deployment fails with:

```
Error: expected DNS record to not already be present but already exists
  with cloudflare_record.cert_validation["*.roboad.ai"]
```

This happens because the ACM validation DNS records already exist in Cloudflare from a previous deployment attempt, but Terraform doesn't know about them (they're not in the Terraform state).

## Solution: Import Existing Records

We need to import the existing DNS records into Terraform state so Terraform can manage them.

### Prerequisites

1. **Cloudflare API Token** with DNS edit permissions
   - Get it from: https://dash.cloudflare.com/profile/api-tokens
   - Required permissions: Zone.DNS (Edit)
   - Export it: `export CLOUDFLARE_API_TOKEN='your_token_here'`

2. **Terraform Cloud credentials** (if using Terraform Cloud)
   - The workspace should be set to "Local execution mode" temporarily for imports
   - OR use Terraform CLI directly

### Step 1: Find Existing DNS Records

Run the import helper script to identify existing ACM validation records:

```bash
cd infra/environments/shared
chmod +x import-dns-records.sh
./import-dns-records.sh
```

This script will:
1. Query Cloudflare API for your zone
2. Find existing ACM validation DNS records
3. Generate Terraform import commands
4. Save them to `/tmp/import_commands.sh`

### Step 2: Review Import Commands

Check the generated import commands:

```bash
cat /tmp/import_commands.sh
```

You should see commands like:

```bash
terraform import 'cloudflare_record.cert_validation["*.roboad.ai"]' <zone_id>/<record_id>
terraform import 'cloudflare_record.cert_validation["roboad.ai"]' <zone_id>/<record_id>
```

### Step 3: Run Terraform Import

**Option A: Using Terraform Cloud (Recommended)**

Since this workspace uses Terraform Cloud, you need to run imports locally:

```bash
# Set your Terraform Cloud token
export TF_TOKEN_app_terraform_io='your_terraform_cloud_token'

# Run the import commands
/tmp/import_commands.sh
```

**Option B: Manual Import (if script fails)**

If the automated script doesn't work, you can manually import each record:

1. Get the Zone ID and Record IDs from Cloudflare API or dashboard
2. Run import commands:

```bash
terraform import 'cloudflare_record.cert_validation["*.roboad.ai"]' <zone_id>/<record_id>
terraform import 'cloudflare_record.cert_validation["roboad.ai"]' <zone_id>/<record_id>
```

### Step 4: Verify Import

Check that the records are now in the Terraform state:

```bash
terraform state list | grep cloudflare_record.cert_validation
```

You should see:

```
cloudflare_record.cert_validation["*.roboad.ai"]
cloudflare_record.cert_validation["roboad.ai"]
```

### Step 5: Plan and Apply

Now run a Terraform plan to verify everything is in sync:

```bash
terraform plan
```

If there are no changes (or only minor updates), the import was successful! You can now proceed with deployment:

```bash
terraform apply
```

## Alternative: Manual Cleanup

If you prefer to start fresh instead of importing, you can delete the existing DNS records:

1. Go to Cloudflare dashboard: https://dash.cloudflare.com
2. Select the `roboad.ai` zone
3. Go to DNS > Records
4. Delete the ACM validation records (CNAME records starting with `_`)
5. Re-run Terraform apply

**Note:** This approach works but is less ideal because Terraform will just recreate the same records anyway.

## Troubleshooting

### "Resource already exists" during import

If import fails with "resource already exists in state", check:

```bash
terraform state list
```

If the resource is already there, you can skip the import or remove it first:

```bash
terraform state rm 'cloudflare_record.cert_validation["*.roboad.ai"]'
```

Then retry the import.

### "Record not found" during import

This means the DNS record doesn't actually exist in Cloudflare. You can:

1. Skip the import
2. Run `terraform apply` to create it

### Cannot access Terraform Cloud

If you can't import via Terraform Cloud (execution mode doesn't support it), you have two options:

1. **Temporarily use local state:**
   - Comment out the `cloud {}` block in `main.tf`
   - Run `terraform init -migrate-state` to copy state locally
   - Run imports
   - Re-enable cloud block and migrate back

2. **Use Cloudflare dashboard** to delete the records and retry

## Prevention

To prevent this in the future:

1. Always complete Terraform deployments (don't Ctrl+C mid-apply)
2. Use `terraform destroy` before major infrastructure changes
3. Consider adding import blocks to the Terraform config (Terraform 1.5+)

## Need Help?

- Check Terraform state: `terraform state list`
- Check Cloudflare DNS: https://dash.cloudflare.com
- Check Terraform Cloud runs: https://app.terraform.io/app/roboad/workspaces/roboad-fast-ws-shared
