variable "ca" {
  description = "List of trusted CAs string to install in the vm"
  type = list(string)
  default = []
}