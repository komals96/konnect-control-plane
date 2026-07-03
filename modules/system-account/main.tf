resource "konnect_system_account" "system_account" {
  name        = var.sa_name
  description = var.sa_desc
}