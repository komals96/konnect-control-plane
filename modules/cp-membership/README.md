# Module: cp-membership

Purpose
- Associate a Kong Konnect Control Plane with a Control Plane Group.

What it does
- Creates the membership relationship between a control plane and a control plane group.
- Uses the IDs produced by the `control-plane` and `control-plane-group` modules.

Inputs
- `cp_id` (string) — ID of the control plane to add to the group
- `cpg_id` (string) — ID of the control plane group

Outputs
- None explicitly defined in this module
- The created membership resource can be referenced by module consumers if needed

Usage
```hcl
module "cp_membership" {
  source = "../../modules/cp-membership"

  cp_id  = module.control_plane.cp_id
  cpg_id = module.control_plane_group.cpg_id
}
