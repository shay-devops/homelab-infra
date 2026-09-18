terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://10.10.10.10:8006/"
  api_token = data.vault_kv_secret_v2.proxmox.data["token"]
  insecure  = true
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name      = each.key
  vm_id     = each.value.vm_id
  node_name = "pve"

  clone {
    vm_id = 9000
    full  = true
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory_mb
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk_gb
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = "shayan"
      keys     = [var.ssh_public_key]
    }
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = each.value.mac_address
  }
}