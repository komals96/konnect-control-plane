resource "konnect_gateway_plugin_opentelemetry" "opentelemetry" {
  enabled = true

  config = {

    metrics = {
      endpoint = var.otel_metrics_endpoint
      push_interval = var.metrics_push_interval
    }

    headers = {
      "X-Auth-Token" = var.metrics_token
    }
  }

  control_plane_id = var.cp_id
}