output "configuration" {
  description = "Cloudinit compatible CephFS shares configurations for mounting"
  sensitive   = true
  value       = templatefile(
    "${path.module}/user_data.yaml.tpl", 
    {
      install_dependencies = var.install_dependencies
      export_loc_path_mons = var.export_loc_path_mons
      shares               = var.shares
    }
  )
}
