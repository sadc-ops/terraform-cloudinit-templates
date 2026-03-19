output "configuration" {
  description = "Cloudinit compatible docker installation script"
  value = templatefile(
    "${path.module}/user_data.yaml.tpl",
    {
      install_dependencies  = var.install_dependencies
      docker_install_script = base64encode(file("${path.module}/install_docker.sh"))
      docker_users          = var.docker_users
    }
  )
}
