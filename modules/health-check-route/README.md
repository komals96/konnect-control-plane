# Module: health-check-route

Purpose
- Create a lightweight health-check route in Kong Konnect.

What it does
- Creates a route resource for health checks or smoke tests.
- Uses the control plane ID, route name, and route path(s).

Inputs
- `cp_id` (string) — Control Plane ID
- `route_name` (string) — name of the route
- `route_paths` (list(string)) — list of paths to expose on the route

Outputs
- `route_id` — ID of the created route (if exposed by module outputs)

Usage
```hcl
module "route" {
  source      = "../../modules/health-check-route"
  cp_id       = module.control_plane.cp_id
  route_name  = var.route_name
  route_paths = var.route_paths
}
```

Notes
- Keep route paths minimal and dedicated to health checks.
- Ensure the target control plane exists before creating the route.
