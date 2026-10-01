resource "konnect_team_role" "this" {
  team_id          = var.team_id
  entity_id        = var.entity_id
  entity_region    = var.entity_region
  entity_type_name = var.entity_type_name
  role_name        = var.role_name
}