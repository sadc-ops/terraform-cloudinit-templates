#cloud-config
merge_how:
 - name: list
   settings: [append, no_replace]
 - name: dict
   settings: [no_replace, recurse_list]

groups:
  - docker

%{ if install_dependencies ~}
write_files:
  - path: /usr/local/bin/install_docker.sh
    owner: root:root
    permissions: "0755"
    encoding: b64
    content: ${docker_install_script}

%{ endif ~}
runcmd:
%{ if install_dependencies ~}
  - /usr/local/bin/install_docker.sh
  - rm /usr/local/bin/install_docker.sh
%{ endif ~}
%{ for user in docker_users ~}
  - usermod -aG docker "${user}"
%{ endfor ~}
