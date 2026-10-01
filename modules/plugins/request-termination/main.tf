resource "konnect_gateway_plugin_request_termination" "request_termination" {
  config = {
    echo = false
    message = "Success"
    status_code = 200
  }
  enabled = true
  instance_name = "req-term-health-${var.cp_type}-${var.environment}"
  protocols = [
    "grpc",
    "grpcs",
    "http",
    "https"
  ]
  tags = [
    var.environment,
    var.cp_type,
    "health check",
    "request termination"
  ]
  control_plane_id = var.cp_id
  
  route = {
    id = var.route_id
  }
}