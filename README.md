# homelab-infra

Production-grade homelab built as a security/IAM engineering portfolio project. Infrastructure is provisioned with Terraform, secrets are managed through HashiCorp Vault, configuration is applied with Ansible, and identity is federated through Okta — against a Proxmox-hosted VM fleet running a k3s Kubernetes cluster.

## Architecture

Five VMs run on a single Proxmox host (pve):

| VM | Role | vCPU | RAM | Notes |
|---|---|---|---|---|
| vault | Secrets management (HashiCorp Vault) | 1 | 1GB | AppRole backend for Terraform/Ansible; native OIDC backend for human SSO login (see Identity & Access below) |
| k3s-control | k3s control-plane (API server, scheduler, etcd) | 1 | 4GB | Resized from 2GB after a capacity incident -- see Incidents below |
| k3s-worker | k3s worker node -- runs all cluster workloads | 2 | 6GB | Resized from 8GB; real usage is well under 2GB, so this still has headroom |
| ansible-control | Control node for Ansible and Terraform | 1 | 1GB | Where IaC is actually run from (see Tooling location) |
| it-docs | BookStack documentation wiki + VaultWarden password manager | 1 | 2GB | Credential vault / runbook documentation; both OIDC-federated except VaultWarden (see below) |

## Repo layout

```
terraform/    Proxmox VM provisioning (main.tf, variables.tf, vault.tf)
ansible/      Configuration management playbooks and roles
k8s/          Kubernetes manifests and Helm values for every workload running on k3s
vault/        Vault ACL policies and OIDC role definitions (non-secret authorization structure, version-controlled)
```

## Tooling location

Terraform and Ansible both run from ansible-control (10.10.10.53). This is a deliberate consolidation -- Terraform originally ran from a separate Windows machine, and was moved onto this host to keep all infrastructure tooling in one place.

Required environment on ansible-control (already configured in ~/.bashrc):

```
export VAULT_ADDR=https://10.10.10.50:8200
export VAULT_CACERT=/home/shayan/homelab-infra/ansible/certs/vault-cert.crt
```

Terraform additionally needs, per session (deliberately never persisted to disk -- see Secrets):

```
export TF_VAR_vault_secret_id="<fresh AppRole SecretID>"
```

## Secrets

- `terraform.tfvars` (in `terraform/`) holds `vault_role_id` -- the Terraform AppRole's RoleID. Gitignored; not sensitive enough to warrant Vault storage itself, but kept out of version control on principle.
- `vault_secret_id` is never written to disk. Generate a fresh one per session:

  ```
  vault write -f auth/approle/role/terraform/secret-id
  export TF_VAR_vault_secret_id="<the returned secret_id>"
  ```

- The Proxmox API token is stored in Vault's KV engine (`homelab/proxmox/terraform-token`) and read by `vault.tf` at plan/apply time -- never hardcoded anywhere in this repo.
- Every Okta app's client_id/client_secret/issuer is stored in Vault under `homelab/okta/<app>` and read by the relevant Ansible role at deploy time -- same pattern, never hardcoded.
- `vault/policies/` and `vault/roles/` hold Vault's own ACL policy and OIDC role *definitions* -- these are authorization structure (paths, capabilities, group bindings), not secrets, and are safe to version-control on the same reasoning security teams use for public IAM policy/RBAC examples: knowing the shape of access grants nothing without a valid credential to exercise it.

## Terraform state -- read before running Terraform on a new host

`terraform.tfstate` is gitignored and currently lives only as a local file on ansible-control. This is a known single point of failure, discovered the hard way: cloning this repo fresh onto a new host with no state file causes `terraform plan` to show all 5 VMs as new resources to create, because Terraform has no record that they already exist -- even though the config and the real infrastructure are identical.

Before running terraform plan/apply from any new host:
1. Copy `terraform.tfstate` (and `terraform.tfstate.backup`, if present) from `ansible-control:~/homelab-infra/terraform/` to the new host, into the same relative path.
2. Copy `terraform.tfvars` the same way.
3. Run `terraform init`, then `terraform plan` -- it should report no changes. If it doesn't, stop and investigate before touching apply.

A proper remote backend (Vault-backed or otherwise) would eliminate this risk entirely and is a known follow-up, not yet implemented.

## Identity & Access -- Okta SSO federation

Four services are federated into a single Okta org (Integrator Free Plan), each via a genuinely different integration mechanism -- deliberately not just the same OIDC config copy-pasted four times:

| App | Mechanism | Group-to-role mapping |
|---|---|---|
| Grafana | Config-file patch (`grafana.ini` via Kustomize) | JMESPath expression against the `groups` claim |
| BookStack | Environment variables (linuxserver.io image, native OIDC auto-discovery) | Literal role-name matching against the `groups` claim |
| Gitea | Registered via CLI/Admin API into Gitea's own database (not a config file) | Built-in admin/regular/restricted tier mapping via `groupClaimName` |
| Vault | Vault's own native `auth/oidc` backend, entirely separate from app-level OIDC | Vault OIDC role bound to an Okta group, mapped to a Vault ACL policy |

Two shared Okta groups (`homelab-admins`, `homelab-viewers`) are used consistently across every app rather than one-off per-app groups. **Vault is the one exception**: it has no viewer tier at all -- only `homelab-admins` can even attempt login, since any authenticated Vault session carries risk regardless of the ACL policy attached to it. That's a deliberate departure from the admin/viewer pattern used everywhere else, not an oversight.

VaultWarden is deliberately excluded from Okta federation: its encryption key is derived client-side from the master password before the server is ever involved, which is fundamentally incompatible with SSO-grants-access federation.

### Vault OIDC specifically

Vault holds every credential in this build, so its OIDC integration got extra care:
- `homelab-admin-policy` (`vault/policies/`) grants broad operational control -- secrets, auth methods, policy management, mounts, audit -- but explicitly denies `sys/seal`, `sys/rekey/*`, `sys/raw/*`, `sys/generate-root/*`, and editing the `root` policy itself. No delete/destroy capability anywhere.
- The OIDC role (`vault/roles/`) binds the `homelab-admins` group to that policy, with a deliberately short TTL (1h/4h max) matching the same short-lived-credential discipline used for AppRole SecretIDs elsewhere in this build.
- Login verified end-to-end through a real debugging chain: a hostname mismatch between what was registered in Okta and what Vault actually serves at (`vault.home.lab` vs. the real `hashicorpvault.home.lab`), a CLI OIDC login that silently depends on the browser and the local callback listener being on the *same* machine (breaks under SSH), and a Vault auth-method visibility setting (`listing_visibility`) that hides newly enabled auth methods from the UI login dropdown by default.

## Internal PKI

cert-manager runs a self-signed root CA + ClusterIssuer chain internally, issuing and auto-renewing TLS certs for every `.home.lab` service (Grafana, Gitea, Uptime Kuma). This exists specifically because Okta rejects non-HTTPS OAuth redirect URIs (except `localhost`) -- TLS was a hard blocker for the SSO work above, not a nice-to-have.

## What's running on k3s

Deployed via `helm template` -> vendored manifest -> `kubectl apply --server-side` for most workloads (not `helm install`, so Helm's release/hook lifecycle isn't in play), except cert-manager and Gitea, which run as live Helm releases (`kubernetes.core.helm`) since both need ongoing `helm upgrade`s and first-class CRD lifecycle management.

- **kube-prometheus** (Prometheus, Grafana, kube-state-metrics, node-exporter) -- cluster and node metrics
- **Loki + Alloy** -- log aggregation and shipping (container logs + systemd journal)
- **Uptime Kuma** -- uptime/availability monitoring, 6 monitors configured
- **cert-manager** -- internal PKI, see above
- **Gitea** -- self-hosted Git server, Okta OIDC-federated, pull-mirrors this repo from GitHub

All pinned to k3s-worker via nodeSelector except DaemonSets (Alloy, node-exporter), which run on every node by design.

## Incidents

**2026-09-23 -- k3s-control PLEG/API-server distress.** After deploying and then tearing down Kyverno (a policy-as-code admission controller, evaluated and ultimately not kept in this build), k3s-control began failing PLEG health checks and timing out on API requests. Root cause: the Kyverno teardown left several ValidatingWebhookConfiguration/MutatingWebhookConfiguration objects registered, pointing at a service that no longer existed. Every matching API write attempted a doomed webhook call before timing out, and that repeated failure cycle manifested as sustained I/O wait and PLEG failure on the control plane. Removing the dangling webhook registrations resolved it immediately (load average dropped from ~3.5 to 0.2). k3s-control's RAM was subsequently resized from 2GB to 4GB as a deliberate resilience buffer, reallocating headroom from the over-provisioned k3s-worker, even though it wasn't the primary root cause.

**2026-09-27 -- Vault OIDC hostname mismatch.** Okta's app registration used `vault.home.lab` as the redirect URI host, but Vault was actually being served at `hashicorpvault.home.lab` -- a naming drift from an earlier DNS decision that nobody caught until login started failing. Diagnosed by comparing the browser's actual address bar against the registered redirect URI rather than assuming the redirect config was the problem, and confirmed against the TLS cert's SAN before fixing it in both Okta and Vault's role config to keep them in sync.

## On the roadmap

- SIEM (Wazuh) with Suricata IDS feeding alerts into a single correlation point
- Vault OIDC reprovisioned via Terraform (see Identity & Access above)
- AI-assisted alert triage (Ollama, local inference)
- Off-site backup (AWS S3)
