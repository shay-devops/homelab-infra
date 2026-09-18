provider "vault" {
  address          = "https://10.10.10.50:8200"
  ca_cert_file     = "C:/Users/shaya/Documents/Projects/Vault/vault-cert.crt"
  skip_child_token = true

  auth_login {
    path = "auth/approle/login"

    parameters = {
      role_id   = var.vault_role_id
      secret_id = var.vault_secret_id
    }
  }
}

data "vault_kv_secret_v2" "proxmox" {
  mount = "homelab"
  name  = "proxmox/terraform-token"
}