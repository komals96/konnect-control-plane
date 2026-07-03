# Module: system-account

Purpose
- Create a Kong Konnect system account for automation and CI/CD workflows.

What it does
- Creates a system account resource.
- Stores metadata such as name, description, and expiry.

Inputs
- `sa_name` (string) — name of the system account
- `sa_desc` (string) — description of the system account
- `sa_expires_at` (string) — expiration timestamp, typically RFC3339

Outputs
- `system_account_id` — ID of the created system account
- any additional outputs defined in the module, such as email or metadata

Usage
```hcl
module "system_account" {
  source        = "../../modules/system-account"
  sa_name       = var.sa_name
  sa_desc       = var.sa_desc
  sa_expires_at = var.sa_expires_at
}
```

Notes
- Keep secret or sensitive values out of source control.
- Use this module before creating tokens or role assignments for the system account.
