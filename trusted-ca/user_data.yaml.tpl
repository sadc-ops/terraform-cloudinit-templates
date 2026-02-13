#cloud-config
merge_how:
 - name: list
   settings: [append, no_replace]
 - name: dict
   settings: [no_replace, recurse_list]

ca_certs:
  remove_defaults: false
  trusted:
%{ for cert in ca_certs ~}
  - |
    ${indent(4,cert)}
%{ endfor ~}