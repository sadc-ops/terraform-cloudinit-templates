network:
  version: 2
  renderer: networkd
  ethernets:
%{ for idx, val in network_interfaces ~}
    eth${idx}:
%{ if val.mac != null ~}
      match:
        macaddress: ${val.mac}
%{ endif ~}
      set-name: ${val.interface}
%{ if val.interface != "" ~}
      set-name: ${val.interface}
%{ else ~}
      set-name: eth${idx}
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
      dhcp4-overrides:
        use-dns: ${val.dhcp4_overrides.use_dns}
        use-mtu: ${val.dhcp4_overrides.use_mtu}
        use-domains: ${val.dhcp4_overrides.use_domains}
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