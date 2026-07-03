resource "konnect_gateway_plugin_file_log" "global_file_log" {

  control_plane_id = var.cp_id

  enabled = true

  config = {
    path   = var.file_log_path
  }

}