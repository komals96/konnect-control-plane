###############################################
# Environment Configuration
###############################################
environment        = "dev"
konnect_sat        = "spat_7DYephaJKnkJK0ZBek4Ds9JpN7Ef49OfNF76TTpoWyTgCGrSf"
konnect_server_url = "https://global.api.konghq.com"


###############################################
# Control Plane Group (CPG)
# Logical grouping of Control Planes
###############################################
cp_group_name = "dev-cloud-cpg"
cpg_desc      = "Kong Konnect control plane group for dev cloud control plane"


###############################################
# Control Plane (CP)
# Core gateway control plane configuration
###############################################
cp_name              = "dev-cloud-cp"
cp_desc              = "Kong Konnect control plane for dev cloud data plane"
auth_type            = "pinned_client_certs"


###############################################
# Teams (RBAC)
# Defines access roles for Control Plane
###############################################
teams = {
  cp_deployer = {
    name        = "dev-cloud-cp-deployer"
    description = "Custom team with Deployer access on the assigned Control Plane."
    role_name   = "Deployer"
  }

  cp_viewer = {
    name        = "dev-cloud-cp-viewer"
    description = "Custom team with Viewer access on the assigned Control Plane."
    role_name   = "Viewer"
  }
}


###############################################
# System Account (Automation / CI-CD)
###############################################
sa_name       = "dev-api-ops-cloud-cp-deployer-sa"
sa_desc       = "Kong Konnect system account for dev control plane"
sa_expires_at = "2027-06-30T03:41:29.965Z"
sa_token_name = "dev-api-ops-cloud-cp-deployer-sat"


###############################################
# Health Check Route
###############################################
route_name  = "health-check-route"
route_paths = ["/health"]


###############################################
# File Log Plugin
###############################################
file_log_path = "/var/log/kong/access.log"


###############################################
# OpenTelemetry (Observability)
###############################################
otel_metrics_endpoint = "http://otel-collector:4318/v1/metrics"
metrics_push_interval  = 10
metrics_token          = "secret-token"
cert_path              = "../../env/dev/cloud-cp/certs/cluster.crt"


###############################################
# Rate Limiting Plugin (Advanced)
###############################################
rl_limit       = [500]
rl_window_size = [3600]
rl_window_type = "fixed"
rl_namespace   = "my-namespace"
rl_strategy    = "local"


###############################################
# RBAC Entity Metadata
# Used for role assignments (Teams + System Account)
###############################################
entity_type_name = "Control Planes"
entity_region    = "us"
