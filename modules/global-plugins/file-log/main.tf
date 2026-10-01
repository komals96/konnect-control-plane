resource "konnect_gateway_plugin_file_log" "global_file_log" {
  config = {
    path = var.file_log_path
    reopen = true
  }
  enabled = true
  instance_name = "file-log-${var.cp_type}-${var.environment}"
  protocols = [
    "grpc",
    "grpcs",
    "http",
    "https"
  ]
  tags = [
    "file-log",
    var.cp_type,
    var.environment
  ]
  control_plane_id = var.cp_id
}
