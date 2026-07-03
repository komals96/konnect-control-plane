# Module: rate-limit-advance

Purpose
- Configure advanced global rate limiting in Kong Konnect.

What it does
- Creates a global rate-limit-advanced plugin.
- Applies rate limiting rules across the configured scope.

Inputs
- `rl_limit` (list(number)) — rate limits to apply
- `rl_window_size` (list(number)) — window sizes for rate limiting
- `rl_window_type` (string) — window type, e.g. `second`, `minute`, `hour`
- `rl_namespace` (string) — namespace for rate limit policy
- `rl_strategy` (string) — rate limiting strategy

Outputs
- `plugin_id` — ID of the created rate-limit-advanced plugin

Usage
```hcl
module "global_rate_limit_advance" {
  source         = "../../modules/global-plugins/rate-limit-advance"
  rl_limit       = var.rl_limit
  rl_window_size = var.rl_window_size
  rl_window_type = var.rl_window_type
  rl_namespace   = var.rl_namespace
  rl_strategy    = var.rl_strategy
}
```

Notes
- Validate list lengths and values against the plugin schema.
- This module configures rate limiting at the global level.
