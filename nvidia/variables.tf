variable "driver_branch" {
  description = "The NVIDIA driver branch number version (e.g. 535, 570, 580) to install"
  type = string

  validation {
    condition     = can(regex("^[0-9]{3}$", var.driver_branch))
    error_message = "driver_branch must be a 3-digit number (e.g. 535, 570, 580)."
  }
}

variable "cuda_version" {
  description = "CUDA toolkit version in APT format (e.g. 12-4, 13-1)"
  type = string
  default = ""

  validation {
    condition     = var.cuda_version == "" || can(regex("^[0-9]+-[0-9]+$", var.cuda_version))
    error_message = "cuda_version must be empty or in APT format (e.g. 12-4, 13-1)."
  }
}

variable "skip_tests" {
  description = "Skip post-install GPU and CUDA verification tests.(default: false)"
  type = bool
  default = false
}

variable "log_file" {
  description = "Log all output to this file (default: /var/log/install_nvidia.log)"
  type = string
  default = "/var/log/install_nvidia.log"
}