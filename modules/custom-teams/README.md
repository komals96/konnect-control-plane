# Module: custom-teams

Purpose
- Create custom Kong Konnect teams for RBAC management.

What it does
- Creates teams from a map of team definitions.
- Exposes team IDs for downstream assignment and role binding.

Inputs
- `teams` (map(object({
    name        = string
    description = string
    role_name   = string
  }))) — map of team definitions

Outputs
- `team_ids` — map of created team IDs keyed by team name or input key

Usage
```hcl
module "konnect_teams" {
  source = "../../modules/custom-teams"
  teams  = var.teams
}
```

Notes
- Provider configuration must be supplied in the root environment (`env/*/provider.tf`).
- Keep team definitions in environment-specific `terraform.tfvars`.
- Use the output `team_ids` for role assignment and membership modules.
```// filepath: c:\Users\V1KSHARMA\Documents\New folder\kong-konnect-inf-itg\modules\custom-teams\README.md
# Module: custom-teams

Purpose
- Create custom Kong Konnect teams for RBAC management.

What it does
- Creates teams from a map of team definitions.
- Exposes team IDs for downstream assignment and role binding.

Inputs
- `teams` (map(object({
    name        = string
    description = string
    role_name   = string
  }))) — map of team definitions

Outputs
- `team_ids` — map of created team IDs keyed by team name or input key

Usage
```hcl
module "konnect_teams" {
  source = "../../modules/custom-teams"
  teams  = var.teams
}
```

Notes
- Keep team definitions in environment-specific `terraform.tfvars`.
- Use the output `team_ids` for role assignment and membership modules.
