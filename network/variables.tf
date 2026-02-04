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
      use_dns     = optional(bool, true)
      use_mtu     = optional(bool, true)
      use_domains = optional(string, "true")
    }), { use_dns = true, use_mtu = true, use_domains = "true" })
  })),

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
      contains(["true", "false", "route"], iface.dhcp4_overrides.use_domains)
    ])
    error_message = "dhcp4_overrides.use_domains must be \"true\", \"false\", or \"route\"."
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

