terraform {
   backend "gcs" {
          bucket = "us-nprd-itg-api-kong-tfstate"
          prefix = "onprem/dev/control-plane"
    }
}
