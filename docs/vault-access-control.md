# Vault access control: human and machine identity

*Part of [homelab-infra](../README.md). Okta login for humans is covered on the [Okta federation page](okta-federation.md).*

**In one sentence:** Vault holds every credential in the lab, so access is split by identity type: people sign in through Okta with a policy that cannot seal, rekey or read raw storage, and automation (Terraform, Ansible) uses short-lived AppRole tokens that can only read the paths each tool needs.

## Why this exists

In an enterprise, the secrets manager is the highest-value target in the environment. Humans and machines get separate identities, each identity gets only the paths it needs, credentials are short-lived, and the dangerous administrative operations (sealing, rekeying, raw storage access) are fenced off even from administrators. This lab simulates that with HashiCorp Vault installed natively on its own VM.

## Design at a glance

| Identity | How it authenticates | Policy | What it can do | Credential lifetime |
|---|---|---|---|---|
| Terraform | AppRole `terraform` | `terraform-policy` | Read-only: the Proxmox API token and the k3s secrets | Token 1 hour (max 4); SecretID valid 90 minutes |
| Ansible | AppRole `ansible` | `ansible-policy` | Read-only, one stanza per prefix (k3s, it-docs, gitea, okta, raspi) | Same pattern as Terraform |
| Human admin | Okta (OIDC), group `homelab-admins` | `homelab-admin-policy` | Manage secrets, auth methods, policies, mounts and audit; no delete or destroy; explicit denies on seal, rekey, raw storage, root generation and the root policy | Token 1 hour (max 4) |

- **Credentials are short-lived; the secrets they read are static.** The values in the KV store (Proxmox token, Okta client secrets, service passwords) are stored secrets. What expires quickly is the credential used to read them. This is AppRole with short-lived tokens, not Vault's dynamic secrets engines.
- **No SecretID on disk.** Terraform's SecretID is generated fresh per session and never written to a file; only the RoleID sits in a gitignored variables file. The Proxmox API token lives in Vault and is read at plan time.
- **Ansible reads secrets at deploy time** through its AppRole, with `no_log` so values stay out of playbook output. Rendered files that contain secrets are gitignored; only templates are tracked.
- **TLS trust is explicit.** Vault's self-signed certificate is trusted by pointing clients at its CA file, not by disabling verification.
- **Authorization structure is in git.** Policies live in `vault/policies/` and OIDC role definitions in `vault/roles/`. They describe paths and group bindings, not secrets.

## The policies in Vault

*The policies, one per identity class:*

<img width="1333" height="817" alt="image" src="https://github.com/user-attachments/assets/d583bbd6-b053-4937-ace5-4e8f1958f3e8" />


*The admin policy's explicit deny rules:*

<img width="1341" height="577" alt="image" src="https://github.com/user-attachments/assets/ecc1603f-8909-467c-8a3b-01662c3948b4" />


*The Terraform AppRole's short token and SecretID lifetimes (RoleID and SecretID not shown):*

<img width="460" height="487" alt="image" src="https://github.com/user-attachments/assets/894e376c-35c3-4629-85b0-7314993abc6a" />


## Design decisions and trade-offs

- **Terraform and Ansible have separate AppRoles.** They have different blast radii: Terraform can create and destroy infrastructure, while Ansible only needs to read configuration secrets. A compromised Ansible token cannot reach the Proxmox API token.
- **One shared Terraform AppRole, not one per service.** I considered per-service roles, created a second Terraform role briefly, and deleted it. The trade-off is simplicity for a one-operator lab at the cost of a slightly wider read scope.
- **Terraform cannot mint child tokens.** The provider is configured with `skip_child_token = true`, because the least-privilege policy deliberately does not grant token creation.
- **Break-glass is outside Vault.** The root token and the unseal keys are stored in a password manager, because Vault cannot hold its own unseal keys. The 3-of-5 unseal path was tested before any OIDC work began.
- **The admin policy has no delete or destroy capability anywhere.** Secrets can be created, read and updated, and KV keeps two versions per key.
- **A deny on unseal is included for completeness but has no effect,** because unsealing happens before authentication.
- **Humans get no viewer tier.** See the [Okta federation page](okta-federation.md).

## Problems hit and fixed

| Symptom | Root cause | Fix |
|---|---|---|
| A `vault kv patch` left a junk key instead of `client_id` | Malformed patch command | Overwrote the secret with a full `vault kv put` |
| Creating the OIDC role failed with "expected a map, got 'string'" | `bound_claims` passed as an inline key=value flag | Wrote the role from a JSON file |
| Every Ansible Vault lookup failed with "vault_addr is undefined" | `group_vars/` sat at the project root, and Ansible only loads it beside the inventory file | Moved it next to the inventory |
| Vault lookups failed with "Could not find a suitable TLS CA certificate bundle" | A stale CA path in `group_vars` left over from an earlier project layout | Corrected the path |
| Terraform config only worked on one machine | A hardcoded Windows CA file path in `vault.tf` | Removed it; the provider reads `VAULT_CACERT` from the environment |
| `VAULT_ADDR` and `VAULT_CACERT` lost in every new SSH session | The variables were exported by hand | Added to `~/.bashrc` |

## What was verified

- **Terraform:** `terraform plan` authenticates with AppRole, reads the Proxmox token from Vault and refreshes real VM state, with no static secret in any tracked or local file.
- **Ansible:** every role that needs a secret (k3s join, it-docs, Gitea, observability, Pi-hole) reads it from Vault through the `ansible` AppRole.
- **Human login:** an Okta login attaches `homelab-admin-policy`; see the [Okta federation page](okta-federation.md).
- **Deny rules:** checked with Vault's own capabilities API from an Okta-authenticated admin session. The dangerous actions themselves were not attempted.

| Path | What it guards | Capabilities returned |
|---|---|---|
| `sys/seal` | Sealing Vault | deny |
| `sys/rekey/init` | Changing the unseal key shares | deny |
| `sys/raw/test` | Direct storage access | deny |
| `sys/generate-root/attempt` | Minting a new root token | deny |
| `sys/policies/acl/root` | Editing the root policy | deny |
| `homelab/data/okta/grafana` | Reading and updating a secret | create, read, update (no delete) |

*The capabilities check in Vault's console, signed in through Okta:*

<img width="931" height="763" alt="image" src="https://github.com/user-attachments/assets/619e6a23-350c-4573-98b6-4d579f0b6d41" />


## Limitations and what an enterprise would do differently

- **Single node with manual unseal.** Vault uses file storage on one VM and must be unsealed with 3 of 5 keys after every restart. An enterprise would run an HA cluster with auto-unseal through a cloud KMS or HSM.
- **Auth backends, roles and policies were created by hand through the CLI.** The policy and role definitions are version-controlled, but the live configuration is not yet code. Reprovisioning through Terraform's Vault provider is planned.
- **The admin policy has a broad read and list catch-all** so new secrets engines are visible. That is wider than strict least privilege; an enterprise would scope it and gate broad reads behind a break-glass or approval flow.
- **Stored secrets are static.** There is no dynamic-secrets engine and no automated rotation of the KV values.
- **SecretIDs are handed over manually each session.** An enterprise would deliver them through a trusted orchestrator using response wrapping.
- **Shared Terraform AppRole.** An enterprise would scope roles per pipeline or environment.
