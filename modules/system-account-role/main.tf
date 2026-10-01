resource "konnect_system_account_role" "this" {
  account_id       = var.system_account_id
  entity_id        = var.entity_id
  entity_region    = var.entity_region
  entity_type_name = var.entity_type_name
  role_name        = var.role_name
}