# Kong Konnect Infra

Purpose
- Automates Kong Konnect control plane, control-plane-group, system accounts, teams, and global plugins for multiple environments (dev, dc-cp...).

Repository layout
- env/<env>/<scope> — environment-specific Terraform (backend, provider, tfvars)
- modules/ — reusable Terraform modules:
  - control-plane
  - control-plane-group
  - cp-membership
  - system-account
  - system-account-token
  - system-account-role
  - custom-teams
  - custom-team-roles
  - global-plugins/*
  - health-check-route
  - plugins/request-termination
  - certificates

Quickstart
1. Edit env/<env>/<scope>/terraform.tfvars with credentials and environment-specific values.
2. From env/<env>/<scope>:
   - terraform init
   - terraform validate
   - terraform plan 
   - terraform apply

Best practices
- Keep provider configuration in env/*, and modules both because by default it takes hashicorp/konnect provider.
- Review modules' inputs/outputs before reuse.
- Use remote state backend for team collaboration.

Contact
- Repo owner: Integration COE Team