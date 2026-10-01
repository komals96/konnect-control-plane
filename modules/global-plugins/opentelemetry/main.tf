resource "konnect_gateway_plugin_opentelemetry" "opentelemetry" {
  config = {
    access_logs = {
      endpoint = var.opentelemetry.access_logs.endpoint
    }

    access_logs_endpoint = var.opentelemetry.access_logs_endpoint
    
    connect_timeout      = var.opentelemetry.connect_timeout
    header_type          = var.opentelemetry.header_type

    headers = var.opentelemetry.headers

    logs_endpoint = var.opentelemetry.logs_endpoint

    metrics = {
      enable_ai_metrics              = var.opentelemetry.metrics.enable_ai_metrics
      enable_bandwidth_metrics       = var.opentelemetry.metrics.enable_bandwidth_metrics
      enable_consumer_attribute      = var.opentelemetry.metrics.enable_consumer_attribute
      enable_latency_metrics         = var.opentelemetry.metrics.enable_latency_metrics
      enable_request_metrics         = var.opentelemetry.metrics.enable_request_metrics
      enable_upstream_health_metrics = var.opentelemetry.metrics.enable_upstream_health_metrics
      endpoint                       = var.opentelemetry.metrics.endpoint
      push_interval                  = var.opentelemetry.metrics.push_interval
    }

    propagation = {
      default_format = var.opentelemetry.propagation.default_format
    }

    queue = {
      concurrency_limit    = var.opentelemetry.queue.concurrency_limit
      initial_retry_delay  = var.opentelemetry.queue.initial_retry_delay
      max_batch_size       = var.opentelemetry.queue.max_batch_size
      max_coalescing_delay = var.opentelemetry.queue.max_coalescing_delay
      max_entries          = var.opentelemetry.queue.max_entries
      max_retry_delay      = var.opentelemetry.queue.max_retry_delay
      max_retry_time       = var.opentelemetry.queue.max_retry_time
    }

    read_timeout  = var.opentelemetry.read_timeout
    send_timeout  = var.opentelemetry.send_timeout
    traces_endpoint = var.opentelemetry.traces_endpoint

    resource_attributes = var.opentelemetry.resource_attributes
    sampling_rate = var.opentelemetry.sampling_rate
    sampling_strategy = var.opentelemetry.sampling_strategy
  }

  enabled       = var.opentelemetry.enabled
  instance_name = var.opentelemetry.instance_name
  protocols     = var.opentelemetry.protocols
  tags          = var.opentelemetry.tags

  control_plane_id = var.cp_id
}
