resource "konnect_system_account_access_token" "system_account_token" {
  account_id       = var.system_account_id
  name             = var.sa_token_name
  expires_at       = var.sa_expires_at
}