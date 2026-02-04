version: 2
renderer: networkd
ethernets:
%{ for idx, val in network_interfaces ~}
  eth${idx}:
%{ if val.interface != "" ~}
    set-name: ${val.interface}
%{ else ~}
    set-name: eth${idx}
%{ endif ~}
%{ if val.ip != "" ~}
    dhcp4: false
%{ else ~}
    dhcp4: true
%{ if val.dhcp_identifier != "" ~}
    dhcp-identifier: ${val.dhcp_identifier}
%{ endif ~}
%{ if try(length(val.dhcp4_overrides), 0) > 0 ~}
    dhcp4-overrides:
%{ if can(val.dhcp4_overrides.use_dns) ~}
      use-dns: ${val.dhcp4_overrides.use_dns}
%{ endif ~}
%{ if can(val.dhcp4_overrides.use_domains) ~}
      use-domains: ${val.dhcp4_overrides.use_domains}
%{ endif ~}
%{ endif ~}
%{ endif ~}
%{ if val.mac != "" ~}
    match:
      macaddress: ${val.mac}
%{ endif ~}
%{ if val.ip != "" ~}
    addresses:
      - ${val.ip}/${val.prefix_length}
%{ endif ~}
%{ if val.gateway != "" ~}
    gateway4: ${val.gateway}
%{ endif ~}
%{ if length(val.dns_servers) > 0 ~}
    nameservers:
      addresses: ${yamlencode(val.dns_servers)}
%{ if length(val.search_domains) > 0 ~}
      search: ${yamlencode(val.search_domains)}
%{ endif ~}
%{ endif ~}
%{ endfor ~}