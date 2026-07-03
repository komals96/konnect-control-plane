resource "konnect_gateway_route" "health_route" {
  control_plane_id = var.cp_id
  name             = var.route_name
  paths            = var.route_paths
  protocols        = ["http", "https"]
}