output "cp_config_yaml" {
  value = yamlencode({
    control_plane_endpoint = module.control_plane_group.control_plane_endpoint
    telemetry_endpoint     = module.control_plane_group.telemetry_endpoint
  })
}

output "system_account_id" {
  value = module.system_account.system_account_id
}

output "verification_targets" {
  description = "Konnect resource IDs consumed by scripts/common/verify_konnect_resources.sh after apply."
  value = {
    control_plane       = { id = module.control_plane.cp_id }
    control_plane_group = { id = module.control_plane_group.cp_group_id }
    system_account      = { id = module.system_account.system_account_id }
    teams               = { for key, team in module.konnect_teams : key => { id = team.team_id } }
    route               = { id = module.route.route_id }
    global_plugins = ["file-log", "opentelemetry", "rate-limiting-advanced"]
  }
}
