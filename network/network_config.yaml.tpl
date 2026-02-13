network:
  version: 2
  renderer: networkd
  ethernets:
%{ for idx, val in network_interfaces ~}
%{ if machine == "q35" ~}
    enp${1 + idx}s0:
%{ else ~}
    ens${3 + idx}:
%{ endif ~}
%{ if val.mac != null ~}
      match:
        macaddress: ${val.mac}
%{ if val.interface != "" ~}
      set-name: ${val.interface}
%{ else ~}
      set-name: eth${idx}
%{ endif ~}
%{ endif ~}
%{ if val.ip != null ~}
      # Static addressing mode
      dhcp4: false
      addresses:
        - ${val.ip}/${val.prefix_length}
      routes:
        - to: default
          via: ${val.gateway}
%{ else ~}
      # DHCP mode
      dhcp4: true
      dhcp-identifier: ${val.dhcp_identifier}
%{ if val.dhcp4_overrides != null ~}
      dhcp4-overrides:
%{ if val.dhcp4_overrides.use_dns != null ~}
        use-dns: ${val.dhcp4_overrides.use_dns}
%{ endif ~}
%{ if val.dhcp4_overrides.use_mtu != null ~}
        use-mtu: ${val.dhcp4_overrides.use_mtu}
%{ endif ~}
%{ if val.dhcp4_overrides.use_domains != null ~}
        use-domains: ${val.dhcp4_overrides.use_domains}
%{ endif ~}
%{ endif ~}
%{ endif ~}
%{ if length(val.dns_servers) > 0 || length(val.search_domains) > 0 ~}
      nameservers:
%{ if length(val.dns_servers) > 0 ~}
        addresses:
%{ for dns in val.dns_servers ~}
          - ${dns}
%{ endfor ~}
%{ endif ~}
%{ if length(val.search_domains) > 0 ~}
        search:
%{ for domain in val.search_domains ~}
          - ${domain}
%{ endfor ~}
%{ endif ~}
%{ endif ~}
%{ endfor ~}