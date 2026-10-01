###############################################
# Environment Configuration
###############################################
##kong-konnect-platform-ops-sat-info = "spat_7DYephaJKnkJK0ZBek4Ds9JpN7Ef49OfNF76TTpoWyTgCGrSf"

environment        = "dev"
konnect_server_url = "https://global.api.konghq.com"


###############################################
# Control Plane Group (CPG)
# Logical grouping of Control Planes
###############################################
cp_type       = "onprem"
cp_group_name = "dev-onprem-cpg"
cpg_desc      = "Kong Konnect control plane group for dev onprem control plane"


###############################################
# Control Plane (CP)
# Core gateway control plane configuration
###############################################
cp_name              = "dev-onprem-cp"
cp_desc              = "Kong Konnect control plane for dev onprem data plane"
auth_type            = "pinned_client_certs"


###############################################
# Teams (RBAC)
# Defines access roles for Control Plane
###############################################
teams = {
  cp_deployer = {
    name        = "dev-onprem-cp-deployer"
    description = "Custom team with Deployer access on the assigned Control Plane."
    role_name   = "Deployer"
    entity_type_name = "Control Planes"
  }

  cp_viewer = {
    name        = "dev-onprem-cp-viewer"
    description = "Custom team with Viewer access on the assigned Control Plane."
    role_name   = "Viewer"
    entity_type_name = "Control Planes"
  }
}


###############################################
# System Account (Automation / CI-CD)
###############################################
sa_name       = "dev-onprem-api-ops-deployer-sa"
sa_desc       = "Kong Konnect system account for dev control plane"


###############################################
# System Account Roles (RBAC)
# Defines API roles for System Account
###############################################
system_account_roles = {
  api_creator = {
    name             = "api-creator"
    role_name        = "Creator"
    entity_type_name = "APIs"
    entity_id        = "*"                # All API Instances
  }

  api_maintainer = {
    name             = "api-maintainer"
    role_name        = "Maintainer"
    entity_type_name = "APIs"
    entity_id        = "*"                # All API Instances
  }

  api_publisher = {
    name             = "api-publisher"
    role_name        = "Publisher"
    entity_type_name = "APIs"
    entity_id        = "*"                # All API Instances
  }
}
###############################################
# System Account Roles (RBAC)
# Defines CP roles for System Account 
###############################################
system_account_roles_cp = {
cp_deployer = {
    name             = "cp-deployer"
    role_name        = "Deployer"
    entity_type_name = "Control Planes"
  }
cp_viewer = {
    name             = "cp-viewer"
    role_name        = "Viewer"
    entity_type_name = "Control Planes"
  } 
cp_admin = {
    name             = "cp-admin"
    role_name        = "Upstream Admin"
    entity_type_name = "Control Planes"
  }
}

###############################################
# System Account Roles (RBAC)
# Defines Portal roles for System Account
###############################################
system_account_roles_portals = {
portal_product_publisher = {
    name             = "portal-product-publisher"
    role_name        = "Product Publisher"
    entity_type_name = "Portals"    
  }
}  



###############################################
# Health Check Route
###############################################
route_name  = "health-check-route"
route_paths = ["/health"]


###############################################
# File Log Plugin
###############################################
file_log_path = "/usr/local/kong/logs/dp_gw.log"


###############################################
# OpenTelemetry (Observability)
###############################################

opentelemetry = {
  enabled       = true
  instance_name = "otel-onprem-dev"

  protocols = [
    "grpc",
    "grpcs",
    "http",
    "https"
  ]

  tags = [
    "otel",
    "onprem",
    "dev"
  ]

  access_logs = {
    endpoint = "https://inf-t-docker-dtotel1a-1.oreillyauto.com:4318/v1/logs"
  }

  access_logs_endpoint = "https://inf-t-docker-dtotel1a-1.oreillyauto.com:4318/v1/logs"

  connect_timeout = 1000
  header_type     = "preserve"
  headers = {
  }

  //Authorization = "{vault://env/otel_token}" // removed from headers

  logs_endpoint = "https://inf-t-docker-dtotel1a-1.oreillyauto.com:4318/v1/logs"

  metrics = {
    enable_ai_metrics              = false
    enable_bandwidth_metrics       = true
    enable_consumer_attribute      = true
    enable_latency_metrics         = true
    enable_request_metrics         = true
    enable_upstream_health_metrics = true

    endpoint      = "https://inf-t-docker-dtotel1a-1.oreillyauto.com:4318/v1/metrics"
    push_interval = 10
  }

  propagation = {
    default_format = "w3c"
  }

  queue = {
    concurrency_limit    = 1
    initial_retry_delay  = 0.01
    max_batch_size       = 200
    max_coalescing_delay = 1
    max_entries          = 10000
    max_retry_delay      = 60
    max_retry_time       = 60
  }

  read_timeout  = 5000
  send_timeout  = 5000

  traces_endpoint = "https://inf-t-docker-dtotel1a-1.oreillyauto.com:4318/v1/traces"

  sampling_strategy = "parent_drop_probability_fallback"
  sampling_rate     = 1

  resource_attributes = {
    "deployment.environment"       = "dev"
    "control_plane.name"           = "dev-onprem-cp"
    "service.namespace"            = "onprem"
  }
}


###############################################
# Rate Limiting Plugin (Advanced)
###############################################
rate_limiting_advanced = {
  enabled       = true
  instance_name = "rate-limit-advanced-dev-onprem"

  protocols = [
    "grpc",
    "grpcs",
    "http",
    "https"
  ]

  tags = [
    "rate-limit-adv",
    "dev",
    "onprem"
  ]

  config = {
    dictionary_name         = "kong_rate_limiting_counters"
    disable_penalty         = false
    enforce_consumer_groups = false
    error_code              = 429
    error_message           = "API rate limit exceeded"
    hide_client_headers     = false
    identifier              = "consumer"

    limit = [
      500
    ]

    lock_dictionary_name = "kong_locks"
    namespace            = "kong-dev-onprem"

    redis = {
      cloud_authentication = {
        auth_provider     = null
        aws_is_serverless = null
      }

      cluster_max_redirections = 5
      connect_timeout          = 2000
      connection_is_proxied    = false
      database                 = 0

      host = null

      keepalive_pool_size = 256

      password = "{vault://env/redis_password}"

      port = null

      read_timeout = 2000
      send_timeout = 2000

      sentinel_master = "mymaster"

      sentinel_nodes = [
        {
          host = "inf-t-redis-dp1-1.oreillyauto.com"
          port = 26380
        },
        {
          host = "inf-t-redis-dp1-2.oreillyauto.com"
          port = 26380
        },
        {
          host = "inf-t-redis-dp1-3.oreillyauto.com"
          port = 26380
        }
      ]

      sentinel_role = "master"

      ssl        = true
      ssl_verify = false
      timeout    = 2000

      username = "{vault://env/redis_username}"
    }

    retry_after_jitter_max = 0
    strategy               = "redis"
    sync_rate              = 0

    window_size = [
      60
    ]

    window_type = "fixed"
  }
}


###############################################
# RBAC Entity Metadata
# Used for role assignments (Teams + System Account)
###############################################
entity_region    = "us"
portal_id        = "b69f5418-7a94-4532-a946-49a9c2c92473"