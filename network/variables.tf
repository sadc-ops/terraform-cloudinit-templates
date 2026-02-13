variable "network_interfaces" {
  description = "List of network interfaces. Each entry has the following keys: interface, prefix_length, ip, mac, gateway (optional) and dns_servers (optional),search_domain (optional), dhcp_identifier (optional), dhcp4_overrides (optional)."
  type        = list(object({
    interface = string,
    prefix_length = optional(number),
    ip  = optional(string),
    mac = optional(string),
    gateway = optional(string),
    dns_servers = optional(list(string), [])
    search_domains = optional(list(string), [])
    dhcp_identifier = optional(string,"duid")
    dhcp4_overrides = optional(object({
      use_dns     = optional(bool)
      use_mtu     = optional(bool)
      use_domains = optional(string)
    }))
  }))

  # DHCP identifier: 'mac' or 'duid' only
  validation {
    condition = alltrue([
      for iface in var.network_interfaces :
      contains(["mac", "duid"], iface.dhcp_identifier)
    ])
    error_message = "DHCP identifier must be 'mac' or 'duid'."
  }

  # use_domains: must be "true", "false", or "route"
  validation {
    condition = alltrue([
      for iface in var.network_interfaces :
      iface.dhcp4_overrides == null || iface.dhcp4_overrides.use_domains == null || contains(["true", "false", "route"], iface.dhcp4_overrides.use_domains)
    ])
    error_message = "If dhcp4_overrides.use_domains is defined, dhcp4_overrides.use_domains must be \"true\", \"false\", or \"route\"."
  }

  #============================================================================
  # STATIC ADDRESSING MODE (ip is specified)
  #============================================================================

  # Static: prefix_length required
  validation {
    condition = alltrue([
      for iface in var.network_interfaces :
      iface.ip == null || iface.prefix_length != null
      ])
    error_message = "Static addressing: 'prefix_length' is required when 'ip' is specified."
  }

  # Static: gateway required
  validation {
    condition = alltrue([
      for iface in var.network_interfaces :
      iface.ip == null || iface.gateway != null
      ])
    error_message = "Static addressing: 'gateway' is required when 'ip' is specified."
  }

  # Static: dns_servers required (at least one)
  validation {
    condition = alltrue([
      for iface in var.network_interfaces :
      iface.ip == null || length(iface.dns_servers) > 0
      ])
    error_message = "Static addressing: at least one 'dns_servers' entry is required when 'ip' is specified."
  }

  #============================================================================
  # DHCP MODE (ip is NOT specified)
  #============================================================================

  # DHCP: prefix_length must NOT be set
  validation {
    condition = alltrue([
      for iface in var.network_interfaces :
      iface.ip != null || iface.prefix_length == null
      ])
    error_message = "DHCP mode: 'prefix_length' cannot be specified without 'ip'. DHCP server provides the prefix length."
  }

  # DHCP: gateway must NOT be set
  validation {
    condition = alltrue([
      for iface in var.network_interfaces :
      iface.ip != null || iface.gateway == null
      ])
    error_message = "DHCP mode: 'gateway' cannot be specified without 'ip'. DHCP server provides the gateway."
  }
}

variable "machine" {
  description = <<-EOT
    The machine type, you normally won't need to set this unless you are running
    on a platform that defaults to the wrong machine type for your template.

    This affects netplan ethernets naming policies because the machine type
    determines the PCI topology, which systemd uses for predictable interface
    naming:

    | Machine | PCI Topology                  | Naming Scheme | Typical Name     |
    |---------|-------------------------------|---------------|------------------|
    | i440FX  | Flat PCI bus 0, slot/device   | ens (slot)    | ens3, ens9       |
    | Q35     | PCIe root ports, bus/device   | enp (path)    | enp1s0, enp2s0   |

    When possible cloud-init netplan configs should match interfaces by MAC
    address to avoid breakage from PCI topology changes.
  EOT
  type    = string
  validation {
    condition     = var.machine == "" || var.machine == "q35"
    error_message = "machine can only be empty or have q35 as value."
  }
  default = ""
}