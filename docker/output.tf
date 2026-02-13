output "configuration" {
  description = "Cloudinit compatible docker installation script"
  value = templatefile(
    "${path.module}/user_data.yaml.tpl",
    {
      docker_install_script = base64encode(file("${path.module}/install_docker.sh"))
    }
  )
}