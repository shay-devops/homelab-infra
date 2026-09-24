variable "ansible_control_ssh_public_key" {
  type    = string
  default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMSknXaQK+DOO4Pi9Qa47WVkDNG8s0MUMSTW3OFxRDqu ansible-control"
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
    k3s-control = {
      vm_id       = 101
      cores       = 1
      memory_mb   = 4096
      disk_gb     = 16
      mac_address = "BC:24:11:00:10:02"
    }
    k3s-worker = {
      vm_id       = 102
      cores       = 2
      memory_mb   = 6144
      disk_gb     = 65
      mac_address = "BC:24:11:00:10:03"
    }
    ansible-control = {
      vm_id       = 103
      cores       = 1
      memory_mb   = 1024
      disk_gb     = 20
      mac_address = "BC:24:11:00:10:04"
    }
    it-docs = {
      vm_id       = 104
      cores       = 1
      memory_mb   = 2048
      disk_gb     = 20
      mac_address = "BC:24:11:00:10:05"
    }
  }
}

variable "vault_role_id" {
  description = "AppRole RoleID for Terraform's Vault authentication"
  type        = string
}

variable "vault_secret_id" {
  description = "AppRole SecretID for Terraform's Vault authentication"
  type        = string
  sensitive   = true
}