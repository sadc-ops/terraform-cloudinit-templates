output "configuration" {
  description = "Cloudinit compatible nvidia drivers/packages installation script"
  value = templatefile(
    "${path.module}/user_data.yaml.tpl",
    {
      nvidia_install_script = base64encode(file("${path.module}/install_nvidia.sh"))
      driver_branch= var.driver_branch
      cuda_version = var.cuda_version
      skip_tests = var.skip_tests
      log_file = var.log_file
    }
  )
}