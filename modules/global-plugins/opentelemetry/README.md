# Module: opentelemetry

Purpose
- Configure OpenTelemetry integration for Kong Konnect.

What it does
- Creates a global OpenTelemetry plugin.
- Sends telemetry data to the configured metrics/export endpoint.

Inputs
- `otel_metrics_endpoint` (string) — OTEL collector or metrics endpoint URL
- `metrics_push_interval` (number) — push interval for metrics
- `metrics_token` (string) — optional token for collector authentication

Outputs
- `plugin_id` — ID of the created OpenTelemetry plugin

Usage
```hcl
module "global_opentelemetry" {
  source                = "../../modules/global-plugins/opentelemetry"
  otel_metrics_endpoint = var.otel_metrics_endpoint
  metrics_push_interval = var.metrics_push_interval
  metrics_token         = var.metrics_token
}
```

Notes
- Confirm the collector endpoint and token are valid before applying.
- This module enables telemetry for the entire Kong deployment scope.
