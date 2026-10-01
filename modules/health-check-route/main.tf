resource "konnect_gateway_route" "health_route" {
  https_redirect_status_code = 426
  methods = [
    "GET"
  ]
  name = "health-check-route"
  path_handling = "v0"
  paths = [
    "/health"
  ]
  preserve_host = false
  protocols = [
    "http",
    #"https"#
  ]
  regex_priority = 0
  request_buffering = true
  response_buffering = true
  strip_path = true
  tags = [
    var.environment,
    var.cp_type,
    "health check"
  ]
  control_plane_id = var.cp_id
}