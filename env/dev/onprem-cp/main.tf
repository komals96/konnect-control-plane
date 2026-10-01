#############################################################
# Control Plane Group
# Creates a Control Plane Group to logically organize
# one or more Control Planes.
#############################################################
module "control_plane_group" {
  source        = "../../../modules/control-plane-group"
  cp_group_name = var.cp_group_name
  cpg_desc      = var.cpg_desc
}

##############################################################
# Control Plane
# Creates the Kong Konnect Control Plane.
##############################################################
module "control_plane" {
  source = "../../../modules/control-plane"

  cp_name   = var.cp_name
  cp_desc   = var.cp_desc
  auth_type = var.auth_type
}

#############################################################
# Control Plane Membership
# Associates the Control Plane with the Control Plane Group.
#############################################################
module "cp_membership" {
  source = "../../../modules/cp-membership"

  cp_group_id = module.control_plane_group.cp_group_id
  cp_id       = module.control_plane.cp_id
}

#############################################################
# Custom Teams
# Creates custom Konnect teams used for RBAC.
#############################################################
module "konnect_teams" {
  source = "../../../modules/custom-teams"

  for_each = var.teams

  name        = each.value.name
  description = each.value.description
}

#############################################################
# Team Role Assignments
# Assigns Control Plane roles to the custom teams.
#############################################################
module "konnect_team_role_assignments" {
  source = "../../../modules/custom-team-roles"

  for_each = var.teams

  team_id          = module.konnect_teams[each.key].team_id
  role_name        = each.value.role_name
  entity_id        = module.control_plane.cp_id
  entity_region    = var.entity_region
  entity_type_name = each.value.entity_type_name

  depends_on = [
    module.konnect_teams
  ]
}

#############################################################
# System Account
# Creates a System Account used for automation and CI/CD.
#############################################################
module "system_account" {
  source = "../../../modules/system-account"

  sa_name = var.sa_name
  sa_desc = var.sa_desc
}


#############################################################
# System Account Role Assignments
# Assigns roles to the System Account.
#############################################################
module "system_account_role_assignments" {
  source = "../../../modules/system-account-role"

  for_each = var.system_account_roles

  system_account_id = module.system_account.system_account_id
  role_name         = each.value.role_name
  entity_type_name  = each.value.entity_type_name
  entity_id         = each.value.entity_id
  entity_region     = var.entity_region

  depends_on = [
    module.system_account
  ]
}

#############################################################
# System Account Role Assignments for cp_deployer
# Assigns roles to the System Account.
#############################################################
module "system_account_role_assignments_cp" {
  source = "../../../modules/system-account-role"

  for_each = var.system_account_roles_cp

  system_account_id = module.system_account.system_account_id
  role_name         = each.value.role_name
  entity_type_name  = each.value.entity_type_name
  entity_id        =  module.control_plane.cp_id
  entity_region     = var.entity_region

  depends_on = [
    module.system_account
  ]
}

#############################################################
# System Account Role Assignments for portals
# Assigns roles to the System Account.
#############################################################
module "system_account_role_assignments_portals" {
  source = "../../../modules/system-account-role"

  for_each = var.system_account_roles_portals

  system_account_id = module.system_account.system_account_id
  role_name         = each.value.role_name
  entity_type_name  = each.value.entity_type_name
  entity_id        =  var.portal_id
  entity_region     = var.entity_region

  depends_on = [
    module.system_account
  ]
}

#############################################################
# Health Check Route
# Creates a route used for health check or testing.
#############################################################
module "route" {
  source = "../../../modules/health-check-route"
  environment   = var.environment
  cp_type       = var.cp_type
  cp_id       = module.control_plane.cp_id
  route_name  = var.route_name
  route_paths = var.route_paths
}

#############################################################
# Route Plugin
# Attaches the Request Termination plugin to the health
# check route.
#############################################################
module "route-plugin" {
  source = "../../../modules/plugins/request-termination"
  environment   = var.environment
  cp_type       = var.cp_type
  cp_id    = module.control_plane.cp_id
  route_id = module.route.route_id
}

#############################################################
# Global Plugins
# Configures plugins that apply across the entire
# Control Plane.
#############################################################

# File Log Plugin
module "file_log_plugin" {
  source = "../../../modules/global-plugins/file-log"

  cp_id         = module.control_plane.cp_id
  file_log_path = var.file_log_path
  environment   = var.environment
  cp_type       = var.cp_type
}

# OpenTelemetry Plugin
module "opentelemetry_plugin" {
  source = "../../../modules/global-plugins/opentelemetry"

  cp_id         = module.control_plane.cp_id
  opentelemetry = var.opentelemetry
}

# Rate Limiting Advanced Plugin
module "rate_limit_plugin" {
  source = "../../../modules/global-plugins/rate-limit-advance"
  cp_id          = module.control_plane.cp_id
  rate_limiting_advanced = var.rate_limiting_advanced
}