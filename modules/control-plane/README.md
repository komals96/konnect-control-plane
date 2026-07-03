# Module: control-plane

Purpose
- Creates a Kong Konnect Control Plane resource and exposes cp_id and related outputs.

Inputs
- cp_name (string) — name of the control plane
- cp_desc (string) — description
- auth_type (string) — authentication strategy (e.g. pinned_client_certs)

Outputs
- cp_id — Control Plane ID
- cp_endpoint — Control Plane Endpoint
- 

Usage
module "control_plane" {
  source = "../../modules/control-plane"
  cp_name = var.cp_name
  cp_desc = var.cp_desc
  auth_type = var.auth_type
}

Notes
- Ensure required API credentials are set in env/* provider.tf.