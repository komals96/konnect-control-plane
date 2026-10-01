terraform {
  required_version = ">= 1.6.0"
  # Required Providers
  # Declares external providers used in this infrastructure
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "~> 3.18"
    }
  }
}