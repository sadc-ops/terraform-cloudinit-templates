variable "install_dependencies" {
  description = "Whether to install/download application dependencies."
  type        = bool
  default     = true
}

variable "docker_users" {
  description = "List of users that should have execute permission on the docker daemon"
  type        = list(string)
  default     = []
}
