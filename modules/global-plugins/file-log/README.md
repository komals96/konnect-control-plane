# Module: file-log

Purpose
- Configure a global file-log plugin in Kong Konnect.

What it does
- Creates a global `file-log` plugin.
- Writes request/response logs to a file path configured in the plugin.

Inputs
- `file_log_path` (string) — local file path for plugin logs

Outputs
- `plugin_id` — ID of the created file-log plugin

Usage
```hcl
module "global_file_log" {
  source        = "../../modules/global-plugins/file-log"
  file_log_path = var.file_log_path
}
```

Notes
- Ensure the target path is writable by the runtime environment.
- This is a global plugin and applies to all applicable Kong resources.
