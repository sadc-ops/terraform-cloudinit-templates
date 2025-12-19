variable "install_dependencies" {
  description = "Whether to install all dependencies in cloud-init"
  type        = bool
}

variable "export_loc_path_mons" {
  description = "Comma-separated list of Ceph monitor addresses"
  type        = string
}

variable "shares" {
  description = "List of CephFS shares with their configurations for mounting"
  sensitive   = true
  type        = list(object({
    name                = string
    export_loc_path_vol = string
    cephx_access_to     = string
    cephx_access_key    = string
    mount_opt_fs        = string
    folder_owner        = string
  }))
}
