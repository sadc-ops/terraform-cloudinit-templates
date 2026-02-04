variable "network_interfaces" {
  description = "List of network interfaces. Each entry has the following keys: interface, prefix_length, ip, mac, gateway (optional) and dns_servers (optional),search_domain (optional), dhcp_identifier (optional), dhcp4_overrides (optional)."
  type        = list(object({
    interface     = string
    prefix_length = string
    ip            = string
    mac           = string
    gateway       = string
    dns_servers   = list(string)
    search_domains = list(string)
    dhcp_identifier = string
    dhcp4_overrides = optional(object({
      use_dns = bool
      use_domains = bool
    }))
  }))
}

