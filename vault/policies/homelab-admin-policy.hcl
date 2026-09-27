path "homelab/data/*" {
  capabilities = ["create", "read", "update", "list"]
}

path "homelab/metadata/*" {
  capabilities = ["read", "list"]
}

path "*" {
  capabilities = ["read", "list"]
}

path "sys/auth" {
  capabilities = ["read", "list"]
}

path "sys/auth/*" {
  capabilities = ["create", "read", "update", "list"]
}

path "sys/policies/acl" {
  capabilities = ["list"]
}

path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "list"]
}

path "sys/mounts" {
  capabilities = ["read", "list"]
}

path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "list"]
}

path "sys/health" {
  capabilities = ["read"]
}

path "sys/audit" {
  capabilities = ["read", "list"]
}

path "sys/seal" {
  capabilities = ["deny"]
}

path "sys/unseal" {
  capabilities = ["deny"]
}

path "sys/generate-root/*" {
  capabilities = ["deny"]
}

path "sys/rekey/*" {
  capabilities = ["deny"]
}

path "sys/raw/*" {
  capabilities = ["deny"]
}

path "sys/policies/acl/root" {
  capabilities = ["deny"]
}
