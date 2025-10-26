# Alternative Fix: Using allow_overwrite

If the import process is too complex or you just want a quick fix, you can try adding the `allow_overwrite` parameter to the Cloudflare DNS record resource.

## Warning

This approach may not work with Cloudflare provider v4.0+ and has known issues. The import method is more reliable.

## Quick Fix

Add `allow_overwrite = true` to the `cloudflare_record.cert_validation` resource in `main.tf`:

```hcl
resource "cloudflare_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = local.cloudflare_zone_id
  name    = each.value.name
  content = each.value.record
  type    = each.value.type
  ttl     = 60
  proxied = false

  allow_overwrite = true  # <-- Add this line

  comment = "ACM certificate validation for ${each.key}"
}
```

## Apply the Change

1. Make the change to `infra/environments/shared/main.tf`
2. Commit and push (if using Terraform Cloud)
3. Retry the deployment

## If This Doesn't Work

Fall back to the import method described in `DNS_IMPORT_GUIDE.md`.

## Known Issues

- The `allow_overwrite` parameter has compatibility issues with newer Cloudflare providers
- May not work with root domain records
- Some users report it doesn't find exact matches even when records exist

That's why **the import method is recommended** as the primary solution.
