resource "konnect_gateway_control_plane_membership" "gatewaycontrolplanemembership" {
  id = var.cp_group_id
  members = [
    {
      id = var.cp_id
    }
  ]
}