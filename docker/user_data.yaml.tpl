#cloud-config
merge_how:
 - name: list
   settings: [append, no_replace]
 - name: dict
   settings: [no_replace, recurse_list]

write_files:
  - path: /usr/local/bin/install_docker.sh
    owner: root:root
    permissions: "0755"
    encoding: b64
    content: ${docker_install_script}

runcmd:
  - /usr/local/bin/install_docker.sh
  - rm /usr/local/bin/install_docker.sh
