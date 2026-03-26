locals {
  interface_names = {
    for idx, val in var.network_interfaces :
    idx => templatestring(var.interface_naming.template, { index = var.interface_naming.start_index + idx })
  }
}

output "configuration" {
  description = "Cloudinit compatible network configurations"
  value = templatefile(
    "${path.module}/network_config.yaml.tpl",
    {
      network_interfaces = var.network_interfaces
      interface_names    = local.interface_names
    }
  )
}