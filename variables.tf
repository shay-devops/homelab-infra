variable "proxmox_api_token" {
  description = "Proxmox API token in the form root@pam!terraform=SECRET"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  type    = string
  default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB6aL2nbE7H1iolDykV/Zqa5LtYJm+yv4kRKGkSQtOzF shayan-homelab"
}

variable "vms" {
  description = "Map of VMs to provision. Key = VM name."
  type = map(object({
    vm_id       = number
    cores       = number
    memory_mb   = number
    disk_gb     = number
    mac_address = string
  }))

  default = {
    vault = {
      vm_id       = 100
      cores       = 1
      memory_mb   = 1024
      disk_gb     = 8
      mac_address = "BC:24:11:00:10:01"
    }
  }
}