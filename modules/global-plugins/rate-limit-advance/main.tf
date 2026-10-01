resource "konnect_gateway_plugin_rate_limiting_advanced" "rate_limiting_advanced" {
  config = {
    dictionary_name             = var.rate_limiting_advanced.config.dictionary_name
    disable_penalty             = var.rate_limiting_advanced.config.disable_penalty
    enforce_consumer_groups     = var.rate_limiting_advanced.config.enforce_consumer_groups
    error_code                  = var.rate_limiting_advanced.config.error_code
    error_message               = var.rate_limiting_advanced.config.error_message
    hide_client_headers         = var.rate_limiting_advanced.config.hide_client_headers
    identifier                  = var.rate_limiting_advanced.config.identifier
    limit                       = var.rate_limiting_advanced.config.limit
    lock_dictionary_name        = var.rate_limiting_advanced.config.lock_dictionary_name
    namespace                   = var.rate_limiting_advanced.config.namespace

    redis = {
      cloud_authentication = {
        auth_provider     = var.rate_limiting_advanced.config.redis.cloud_authentication.auth_provider
        aws_is_serverless = var.rate_limiting_advanced.config.redis.cloud_authentication.aws_is_serverless
      }
      cluster_max_redirections = var.rate_limiting_advanced.config.redis.cluster_max_redirections
      connect_timeout          = var.rate_limiting_advanced.config.redis.connect_timeout
      connection_is_proxied    = var.rate_limiting_advanced.config.redis.connection_is_proxied
      database                 = var.rate_limiting_advanced.config.redis.database
      host                      = var.rate_limiting_advanced.config.redis.host
      keepalive_pool_size      = var.rate_limiting_advanced.config.redis.keepalive_pool_size

      password = var.rate_limiting_advanced.config.redis.password
      port                      = var.rate_limiting_advanced.config.redis.port
      read_timeout  = var.rate_limiting_advanced.config.redis.read_timeout
      send_timeout  = var.rate_limiting_advanced.config.redis.send_timeout
      sentinel_master = var.rate_limiting_advanced.config.redis.sentinel_master

      sentinel_nodes = var.rate_limiting_advanced.config.redis.sentinel_nodes

      sentinel_role = var.rate_limiting_advanced.config.redis.sentinel_role
      ssl           = var.rate_limiting_advanced.config.redis.ssl
      ssl_verify    = var.rate_limiting_advanced.config.redis.ssl_verify
      timeout       = var.rate_limiting_advanced.config.redis.timeout
      username      = var.rate_limiting_advanced.config.redis.username
    }

    retry_after_jitter_max = var.rate_limiting_advanced.config.retry_after_jitter_max
    strategy               = var.rate_limiting_advanced.config.strategy
    sync_rate              = var.rate_limiting_advanced.config.sync_rate
    window_size            = var.rate_limiting_advanced.config.window_size
    window_type            = var.rate_limiting_advanced.config.window_type
  }

  enabled = var.rate_limiting_advanced.enabled

  instance_name = var.rate_limiting_advanced.instance_name

  protocols = var.rate_limiting_advanced.protocols

  tags = var.rate_limiting_advanced.tags

  control_plane_id = var.cp_id
}