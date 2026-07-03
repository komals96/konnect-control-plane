resource "konnect_gateway_plugin_request_termination" "request_termination" {
  enabled = true

  config = {
    status_code = 200
    message     = "\"Success\""
  }

  tags             = []
  control_plane_id = var.cp_id

  route = {
    id = var.route_id
  }
}