variable "cp_id" {
  type = string
}

variable "rl_namespace" {
  type    = string
}

variable "rl_limit" {
  type = list(number)
}

variable "rl_window_size" {
  type = list(number)
}

variable "rl_window_type" {
  type    = string
}

variable "rl_strategy" {
  type  = string
}
