variable "cp_id" {
  type = string
}

variable "opentelemetry" {
  description = "OpenTelemetry plugin configuration"

  type = object({
    enabled       = bool
    instance_name = string
    protocols     = list(string)
    tags          = list(string)

    access_logs = object({
      endpoint = string
    })

    access_logs_endpoint = string
    connect_timeout      = number
    header_type          = string

    headers = map(string)

    logs_endpoint = string

    metrics = object({
      enable_ai_metrics              = bool
      enable_bandwidth_metrics       = bool
      enable_consumer_attribute      = bool
      enable_latency_metrics         = bool
      enable_request_metrics         = bool
      enable_upstream_health_metrics = bool
      endpoint                       = string
      push_interval                  = number
    })

    propagation = object({
      default_format = string
    })

    queue = object({
      concurrency_limit    = number
      initial_retry_delay  = number
      max_batch_size       = number
      max_coalescing_delay = number
      max_entries          = number
      max_retry_delay      = number
      max_retry_time       = number
    })

    read_timeout      = number
    send_timeout      = number
    traces_endpoint   = string
    sampling_strategy = string
    sampling_rate     = number

    resource_attributes = map(string)
  })
}
