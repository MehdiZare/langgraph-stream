# Project Guidelines for Claude

## Database Migrations

### Supabase Migrations

**IMPORTANT**: Never create migration files manually. Always use the Supabase CLI to generate migrations.

#### Creating a new migration:

```bash
supabase migration new <migration_name>
```

This will create a timestamped migration file in `supabase/migrations/` that you can then edit with your SQL.

#### Example workflow:

1. Create empty migration:
   ```bash
   supabase migration new create_users_table
   ```

2. Edit the generated file in `supabase/migrations/YYYYMMDDHHMMSS_create_users_table.sql`

3. Apply migration:
   ```bash
   supabase db reset  # for local development
   # or
   supabase db push   # for remote database
   ```

#### Why use the CLI?

- Ensures consistent timestamp-based ordering
- Prevents migration conflicts
- Maintains proper Supabase project structure
- Integrates with version control better

## Storage

### S3 Integration

**S3 Folder Structure Pattern:**

All files for a scan are stored in a single folder using the scan UUID:

```
s3://{bucket_name}/scans/{scan_id}/
  ├── screenshot.png
  ├── page.html
  ├── raw_data.json
  └── metadata.json
```

**Implementation Guidelines:**

- Use scan UUID as the folder name: `scans/{scan_id}/`
- Store all related files (screenshots, HTML, raw Steel data) in this folder
- Construct S3 paths programmatically using scan ID - no need to store individual keys in DB
- Use boto3 for Python S3 operations
- Store filenames or file metadata in the `scan_data` JSONB field if needed

**Example Python code:**

```python
def get_scan_s3_path(scan_id: str, filename: str) -> str:
    return f"scans/{scan_id}/{filename}"

# Upload screenshot
s3_client.upload_file(
    local_file,
    bucket_name,
    get_scan_s3_path(scan_id, "screenshot.png")
)

# Download file
s3_client.download_file(
    bucket_name,
    get_scan_s3_path(scan_id, "page.html"),
    local_destination
)
```

### Database Schema Patterns

- Use JSONB for flexible data storage (scan results, metadata)
- Always include `created_at` and `updated_at` timestamps
- Use foreign key constraints for relationships
- Consider indexes on frequently queried fields
- Support anonymous scans with nullable `user_id` and `session_id` tracking