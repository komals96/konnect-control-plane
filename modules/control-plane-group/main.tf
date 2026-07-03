#############################################
# Create Control Plane Group
#############################################

resource "konnect_gateway_control_plane" "cp_group" {

  name        = var.cp_group_name
  description = var.cpg_desc

  cluster_type = "CLUSTER_TYPE_CONTROL_PLANE_GROUP"
  
}