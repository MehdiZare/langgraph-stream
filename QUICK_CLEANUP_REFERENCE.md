# Quick Cleanup Reference

## TL;DR - Fastest Path to Recovery

Your Terraform Cloud workspace has corrupted state. Here's the fastest way to fix it:

### Option A: Complete Cleanup (Recommended - Everything)

```bash
cd scripts

# 1. Set your AWS and Terraform Cloud credentials
export AWS_REGION=us-east-2
export TF_API_TOKEN='get_from_https://app.terraform.io/app/settings/tokens'

# 2. See what exists (optional but recommended)
./list-shared-resources.sh

# 3. Delete ALL AWS resources (shared, PR, prod)
./cleanup-all-aws-resources.sh
# Type 'DELETE EVERYTHING' when prompted

# 4. Force delete the corrupted workspace(s)
./force-delete-shared-workspace.sh

# 5. Push a commit or trigger deployment
# Terraform Cloud will create fresh workspace automatically
```

### Option B: Selective Cleanup (Shared Only)

```bash
cd scripts

# 1. Set your credentials
export TF_API_TOKEN='get_from_https://app.terraform.io/app/settings/tokens'

# 2. See what AWS resources exist
./list-shared-resources.sh

# 3. Delete AWS resources via Console or CLI
# See SHARED_WORKSPACE_CLEANUP.md for detailed commands
# IMPORTANT: Must delete NAT gateways (they cost money!)

# 4. Force delete the corrupted workspace
./force-delete-shared-workspace.sh

# 5. Push a commit or trigger deployment
# Terraform Cloud will create fresh workspace automatically
```

## What's Wrong

- Workspace: `roboad-fast-ws-shared`
- Problem: State has old v4 resources, v5 provider can't read them
- Error: `no schema available for cloudflare_record`
- Can't destroy: State too corrupted to plan

## What's Fixed

✅ Code is already fixed (commits `5430e88`, `4e0a0f4`, `1b67a48`):
- Changed `value` → `content` parameter
- Changed `record.hostname` → `record.name`
- Hardcoded Cloudflare zone ID (v5 zone lookup broken)

## Critical AWS Resources to Delete

### What the Complete Cleanup Script Deletes
The `cleanup-all-aws-resources.sh` script deletes **everything**:
- ✅ 2 NAT Gateways (~$0.09/hour) ⚠️ **Costs money!**
- ✅ 2 VPCs and all networking (subnets, route tables, IGWs, security groups)
- ✅ 3 ECS Clusters (shared, pr-3, prod) and all services
- ✅ Load balancers and target groups
- ✅ ACM certificate (FAILED status)
- ✅ IAM roles (2 roles)
- ✅ Secrets Manager secrets (10 secrets)
- ✅ CloudWatch log groups
- ✅ S3 bucket and ALL scan data
- ✅ Elastic IPs

### What's Preserved
- ✅ ECR repository (has your Docker images!)

## Order of Operations

1. **List** resources → See what exists
2. **Delete AWS** resources → Prevent orphaned resources
3. **Force delete** workspace → Remove corrupted state
4. **Deploy fresh** → Terraform Cloud auto-creates new workspace

## Expected Timeline

- List resources: 30 seconds
- Delete AWS resources: 5-10 minutes (NAT gateways are slow)
- Force delete workspace: 10 seconds
- Fresh deployment: 5-10 minutes
- ACM cert validation: 5-30 minutes
- **Total: 15-50 minutes**

## After Cleanup

Once workspace is recreated:
1. All infrastructure will be rebuilt identically
2. Update Secrets Manager values (they're recreated but empty)
3. ACM certificate will validate via Cloudflare DNS
4. PR environments can deploy once shared completes

## Files to Read

- **`scripts/cleanup-all-aws-resources.sh`** - ⭐ Complete AWS cleanup (everything)
- `scripts/list-shared-resources.sh` - See what exists
- `scripts/force-delete-shared-workspace.sh` - Delete workspace
- `SHARED_WORKSPACE_CLEANUP.md` - Complete detailed guide
- `scripts/cleanup-aws-resources.sh` - PR environment cleanup (legacy)

## Verification Commands

```bash
# Check workspace is deleted
curl -H "Authorization: Bearer $TF_API_TOKEN" \
  https://app.terraform.io/api/v2/organizations/roboad/workspaces/roboad-fast-ws-shared

# Should return 404 Not Found

# Check AWS resources are cleaned up
./scripts/list-shared-resources.sh

# Should show mostly empty results
```

## If Something Goes Wrong

### Workspace won't delete
- Check API token has admin permissions
- Try unlocking workspace first (script does this automatically)

### AWS resources won't delete
- NAT gateways take time - wait 2-5 minutes
- VPC delete fails if NAT gateways still exist
- Delete via Console if CLI fails

### New deployment still fails
- Verify workspace actually deleted (check TF Cloud UI)
- Check code has latest commits (`git log --oneline -5`)
- Verify provider versions in `.terraform.lock.hcl`

## Cost Warning

⚠️ **NAT Gateways cost ~$0.045/hour** - Make sure they're deleted!

Check for running NAT gateways:
```bash
aws ec2 describe-nat-gateways --region us-east-2 \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[].{ID:NatGatewayId,State:State}'
```

## Success Criteria

✅ Workspace deleted from Terraform Cloud
✅ No AWS resources with `roboad-backend` tag
✅ Fresh deployment succeeds
✅ ACM certificate validates
✅ Cloudflare DNS records created

## Questions?

- Review full guide: `SHARED_WORKSPACE_CLEANUP.md`
- Check Terraform Cloud: https://app.terraform.io/app/roboad
- Check AWS Console: https://console.aws.amazon.com
- Cloudflare dashboard: https://dash.cloudflare.com
