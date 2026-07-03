# Module: system-account-token

Purpose
- Generate a token for a Kong Konnect system account.

What it does
- Creates a system account token tied to a system account.
- Supports expiration and naming for token management.

Inputs
- `system_account_id` (string) — ID of the system account
- `sa_token_name` (string) — name for the token
- `sa_expires_at` (string) — expiration timestamp, typically RFC3339

Outputs
- `token_value` — the generated token value (sensitive)
- `token_id` — ID of the created token

Usage
```hcl
module "system_account_token" {
  source            = "../../modules/system-account-token"
  system_account_id = module.system_account.system_account_id
  sa_token_name     = var.sa_token_name
  sa_expires_at     = var.sa_expires_at
}
```

Notes
- Treat token outputs as sensitive and do not expose them in logs.
- Rotate tokens regularly and use secure storage for the generated value.
