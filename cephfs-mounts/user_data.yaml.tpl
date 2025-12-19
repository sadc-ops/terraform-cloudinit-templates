#cloud-config
merge_how:
 - name: list
   settings: [append, no_replace]
 - name: dict
   settings: [no_replace, recurse_list]

write_files:
  - path: /etc/ceph/ceph.conf
    owner: root:root
    permissions: "0400"
    content: |
      [global]
      admin socket = /var/run/ceph/$cluster-$name-$pid.asok
      client reconnect stale = true
      debug client = 0/2
      fuse big writes = true
      mon host = ${export_loc_path_mons}
      [client]
      quota = true
  - path: /etc/ceph/ceph.keyring
    owner: root:root
    permissions: "0400"
    content: |
%{ for share in shares ~}
      [client.${share.cephx_access_to}]
          key = ${share.cephx_access_key}
%{ endfor ~}

%{ if install_dependencies ~}
packages:
  - libcephfs2
  - python3-cephfs
  - ceph-common
  - python3-ceph-argparse
%{ endif ~}

runcmd:
%{ for share in shares ~}
%{ if share.mount_opt_fs != "" ~}
  - NAMESPACE_ARG=,mds_namespace=${share.mount_opt_fs}
%{ endif ~}
  - mkdir -p /mnt/${share.name}
  - chown ${share.folder_owner}:${share.folder_owner} /mnt/${share.name}
  - echo "${share.export_loc_path_vol} /mnt/${share.name}/ ceph name=${share.cephx_access_to},x-systemd.device-timeout=30,x-systemd.mount-timeout=30,noatime,_netdev,rw$${NAMESPACE_ARG} 0  2" >> /etc/fstab
%{ endfor ~}
  - mount -a
