output "cp_group_id" {
  value = konnect_gateway_control_plane.cp_group.id
}

output "control_plane_endpoint" {
  value = konnect_gateway_control_plane.cp_group.config.control_plane_endpoint
}

output "telemetry_endpoint" {
  value = konnect_gateway_control_plane.cp_group.config.telemetry_endpoint 
}
