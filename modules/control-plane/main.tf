#############################################
# Create Control Plane
#############################################

resource "konnect_gateway_control_plane" "cp" {
  name = var.cp_name
  cluster_type = "CLUSTER_TYPE_HYBRID"
  cloud_gateway = false
  description = var.cp_desc
  auth_type    = var.auth_type

  proxy_urls = [
    {
      host     = "localhost",
      port     = 8000,
      protocol = "http"
    }
  ]
}
