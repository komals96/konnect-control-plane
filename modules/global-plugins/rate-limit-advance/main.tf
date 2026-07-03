resource "konnect_gateway_plugin_rate_limiting_advanced" "rate_limiting_advanced" {
  enabled = true

  config = {
    limit = var.rl_limit
    window_size = var.rl_window_size
    window_type = lower(var.rl_window_type)
    namespace = var.rl_namespace
    strategy  = var.rl_strategy
  }
  tags = []

  control_plane_id = var.cp_id
}