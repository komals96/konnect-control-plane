# Module: system-account-role

Purpose
- Assign a role to a Kong Konnect system account on a target entity.

What it does
- Creates a role assignment between a system account and an entity.
- Uses entity metadata such as type and region.

Inputs
- `system_account_id` (string) — ID of the system account
- `entity_id` (string) — ID of the target entity
- `entity_type_name` (string) — entity type name, e.g. `Control Planes`
- `entity_region` (string) — region of the target entity
- `role_name` (string) — name of the role to assign

Outputs
- `role_assignment_id` — ID of the created role assignment

Usage
```hcl
module "system_account_role_assignment" {
  source             = "../../modules/system-account-role"
  system_account_id  = module.system_account.system_account_id
  entity_id          = module.control_plane.cp_id
  entity_type_name   = "Control Planes"
  entity_region      = var.entity_region
  role_name          = "Deployer"
}
```

Notes
- Provider configuration must be supplied in the root environment (`env/*/provider.tf`).
- Ensure the entity type and region match the API expectations.
- Use this module after the system account and target entity exist.
```// filepath: c:\Users\V1KSHARMA\Documents\New folder\kong-konnect-inf-itg\modules\system-account-role\README.md
# Module: system-account-role

Purpose
- Assign a role to a Kong Konnect system account on a target entity.

What it does
- Creates a role assignment between a system account and an entity.
- Uses entity metadata such as type and region.

Inputs
- `system_account_id` (string) — ID of the system account
- `entity_id` (string) — ID of the target entity
- `entity_type_name` (string) — entity type name, e.g. `Control Planes`
- `entity_region` (string) — region of the target entity
- `role_name` (string) — name of the role to assign

Outputs
- `role_assignment_id` — ID of the created role assignment

Usage
```hcl
module "system_account_role_assignment" {
  source             = "../../modules/system-account-role"
  system_account_id  = module.system_account.system_account_id
  entity_id          = module.control_plane.cp_id
  entity_type_name   = "Control Planes"
  entity_region      = var.entity_region
  role_name          = "Deployer"
}
```

Notes
- Ensure the entity type and region match the API expectations.
- Use this module after the system account and target entity exist.
