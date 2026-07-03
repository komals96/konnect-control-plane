# Module: control-plane-group

Purpose
- Create a Kong Konnect Control Plane Group for logical organization of one or more control planes.

What it does
- Creates a Control Plane Group resource.
- Exposes the control plane group ID for membership association.

Inputs
- `cp_group_name` (string) — name of the control plane group
- `cpg_desc` (string) — description of the control plane group

Outputs
- `cpg_id` — identifier of the created control plane group

Usage
```hcl
module "control_plane_group" {
  source       = "../../modules/control-plane-group"
  cp_group_name = var.cp_group_name
  cpg_desc      = var.cpg_desc
}
```

Notes
- Provider configuration must be provided in the root environment (`env/*/provider.tf`).
- Use this module together with `cp-membership` to attach control planes to the group.
- Keep module inputs focused on group metadata only.
```// filepath: c:\Users\V1KSHARMA\Documents\New folder\kong-konnect-inf-itg\modules\control-plane-group\README.md
# Module: control-plane-group

Purpose
- Create a Kong Konnect Control Plane Group for logical organization of one or more control planes.

What it does
- Creates a Control Plane Group resource.
- Exposes the control plane group ID for membership association.

Inputs
- `cp_group_name` (string) — name of the control plane group
- `cpg_desc` (string) — description of the control plane group

Outputs
- `cpg_id` — identifier of the created control plane group

Usage
```hcl
module "control_plane_group" {
  source       = "../../modules/control-plane-group"
  cp_group_name = var.cp_group_name
  cpg_desc      = var.cpg_desc
}
```

Notes
- Use this module together with `cp-membership` to attach control planes to the group.
- Keep module inputs focused on group metadata only.
