# Module: custom-team-roles

Purpose
- Assign roles to one or more teams for a specific Kong Konnect entity.

What it does
- Creates team role assignments for a Control Plane or other Konnect entity.
- Uses entity metadata and role names to attach teams to the target.

Inputs
- `entity_id` (string) — ID of the target entity
- `entity_type_name` (string) — entity type name, e.g. `"Control Planes"`
- `entity_region` (string) — region of the target entity
- `role_name` (string) — role to assign to the teams
- `team_ids` (list(string)) — list of team IDs receiving the role

Outputs
- `role_assignment_ids` — list of created role assignment IDs (if exposed)

Usage
```hcl
module "custom_team_roles" {
  source          = "../../modules/custom-team-roles"
  entity_id       = module.control_plane.cp_id
  entity_type_name = "Control Planes"
  entity_region   = var.entity_region
  role_name       = "Deployer"
  team_ids        = [for t in module.konnect_teams.team_ids : t]
}
```

Notes
- Use this module after teams are created.
- Ensure `entity_type_name` matches the API expected type for role assignments.
