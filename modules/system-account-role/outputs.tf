output "system_account_role_assignment_id" {
  description = "Kong Konnect system account role assignment ID."
  value       = konnect_system_account_role.this.id
}
 
output "system_account_id" {
  description = "Kong Konnect system account ID."
  value       = konnect_system_account_role.this.account_id
}
 
output "role_name" {
  description = "Role assigned to the system account."
  value       = konnect_system_account_role.this.role_name
}