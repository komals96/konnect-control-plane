###############################################
# Provider / Authentication
###############################################

variable "konnect_server_url" {
  type    = string
  default = "https://global.api.konghq.com"
}

###############################################
# Environment
###############################################

variable "environment" {
  type = string
}

###############################################
# Control Plane Group
###############################################

variable "cp_type" {
  type    = string
}

variable "cp_group_name" {
  type    = string
  default = null
}

variable "cpg_desc" {
  type = string
}

###############################################
# Control Plane
###############################################

variable "cp_name" {
  type    = string
  default = null
}

variable "cp_desc" {
  type = string
}

variable "auth_type" {
  type = string
}

###############################################
# Teams
###############################################

variable "teams" {
  description = "Custom teams to create in Kong Konnect along with their control plane role."

  type = map(object({
    name        = string
    description = string
    role_name   = string
    entity_type_name = string
  }))
}

###############################################
# System Account
###############################################

variable "sa_name" {
  type = string
}

variable "sa_desc" {
  type = string
}

###############################################
# System Account Role
###############################################

#############################################################
# System Account Role Assignments Variables
#############################################################

variable "system_account_roles" {
  description = "System account roles to assign."

  type = map(object({
    role_name        = string
    entity_type_name = string
    entity_id        = string
  }))
}

variable "system_account_roles_cp" {
  description = "System account roles to assign."

  type = map(object({
    role_name        = string
    name        = string
    entity_type_name = string
  }))
}

variable "system_account_roles_portals" {
  description = "System account roles to assign."

  type = map(object({
    role_name        = string
    entity_type_name = string
  }))
}



###############################################
# Route
###############################################

variable "route_name" {
  type    = string
  default = null
}

variable "route_paths" {
  type = list(string)
}

###############################################
# File Log Plugin
###############################################

variable "file_log_path" {
  type = string
}

###############################################
# OpenTelemetry Plugin
###############################################

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

###############################################
# Rate Limiting Advanced Plugin
###############################################

variable "rate_limiting_advanced" {
  description = "Rate limiting advanced plugin configuration"

  type = object({
    enabled      = bool
    instance_name = string
    protocols    = list(string)
    tags         = list(string)

    config = object({
      dictionary_name             = string
      disable_penalty             = bool
      enforce_consumer_groups     = bool
      error_code                  = number
      error_message               = string
      hide_client_headers         = bool
      identifier                  = string
      limit                       = list(number)
      lock_dictionary_name        = string
      namespace                   = string

      redis = object({
        cloud_authentication = object({
          auth_provider     = string
          aws_is_serverless = bool
        })

        cluster_max_redirections = number
        connect_timeout          = number
        connection_is_proxied    = bool
        database                 = number
        host                     = string
        keepalive_pool_size      = number
        password                 = string
        port                     = number
        read_timeout             = number
        send_timeout             = number
        sentinel_master          = string

        sentinel_nodes = list(object({
          host = string
          port = number
        }))

        sentinel_role = string
        ssl           = bool
        ssl_verify    = bool
        timeout       = number
        username      = string
      })

      retry_after_jitter_max = number
      strategy               = string
      sync_rate              = number
      window_size             = list(number)
      window_type             = string
    })
  })
}

###############################################
# Entity Configuration
###############################################

variable "entity_region" {
  type = string
}

variable "portal_id"{
  type = string
}