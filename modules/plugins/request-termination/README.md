# Module: request-termination

Purpose
- Configure a request-termination plugin in Kong Konnect.

What it does
- Creates a plugin that terminates requests with a configured status code and message.
- Can be used for controlled failure responses or testing.

Inputs
- `status_code` (number) — HTTP status code to return
- `message` (string) — response body message for terminated requests

Outputs
- `plugin_id` — ID of the created plugin (if exposed by module outputs)

Usage
```hcl
module "request_termination" {
  source      = "../../modules/plugins/request-termination"
  status_code = var.status_code
  message     = var.message
}
```

Notes
- Use this module carefully; it will stop request processing for matched traffic.
- Validate the plugin scope and attach it only where intended.
