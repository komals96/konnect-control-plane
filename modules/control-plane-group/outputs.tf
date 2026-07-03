output "cp_group_id" {
  value = konnect_gateway_control_plane.cp_group.id
}

output "control_plane_endpoint" {
  value = konnect_gateway_control_plane.cp_group.config.control_plane_endpoint
}

#output "cluster_server_name" {
#  value = konnect_gateway_control_plane.cp_group.cluster_server_name
#}

#output "cluster_telemetry_server_name" {
#  value = konnect_gateway_control_plane.cp_group.cluster_telemetry_server_name
#}

output "telemetry_endpoint" {
  value = konnect_gateway_control_plane.cp_group.config.telemetry_endpoint 
}
