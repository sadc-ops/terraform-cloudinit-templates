output "configuration" {
  description = "Cloudinit compatible trusted ca installation"
  value = templatefile(
    "${path.module}/user_data.yaml.tpl",
    {
      ca_certs = var.ca
    }
  )
}