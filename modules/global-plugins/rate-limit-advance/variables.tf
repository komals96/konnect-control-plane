variable "cp_id" {
  type = string
}

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