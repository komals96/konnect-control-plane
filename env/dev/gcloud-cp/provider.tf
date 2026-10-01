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

provider "konnect" {

  # System Account Access Token used for authentication
  # Recommended: inject via secret manager (not hardcoded)
  # Konnect API base URL
  server_url = var.konnect_server_url
}