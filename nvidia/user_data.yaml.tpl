#cloud-config
merge_how:
 - name: list
   settings: [append, no_replace]
 - name: dict
   settings: [no_replace, recurse_list]

write_files:
  - path: /usr/local/bin/install_nvidia.sh
    owner: root:root
    permissions: "0755"
    encoding: b64
    content: ${nvidia_install_script}

# Upgrading packages in order to install nvidia drivers on the latest versions of packages and kernel
package_update: true
package_upgrade: true
package_reboot_if_required: true

runcmd:
  - [ /usr/local/bin/install_nvidia.sh, --driver-branch, "${driver_branch}", %{ if cuda_version != "" } --cuda-version, "${cuda_version}", %{ endif } %{ if skip_tests } --skip_tests, %{ endif } --log-file, "${log_file}" ]
  - rm /usr/local/bin/install_nvidia.sh

# Installing nvidia drivers requires reboot
power_state:
    delay: now
    mode: reboot
    message: Rebooting after cloud-init completion
    condition: true