output "system_account_token" {
  sensitive = true
  value     = konnect_system_account_access_token.system_account_token.token
}