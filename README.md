# homelab-infra

Production-grade homelab built as a security/IAM engineering portfolio project. Infrastructure is provisioned with Terraform, secrets are managed through HashiCorp Vault, and configuration is applied with Ansible against a Proxmox-hosted VM fleet running a k3s Kubernetes cluster.

## Architecture

Five VMs run on a single Proxmox host (pve):

| VM | Role | vCPU | RAM | Notes |
|---|---|---|---|---|
| vault | Secrets management (HashiCorp Vault) | 1 | 1GB | AppRole auth backend for Terraform and Ansible |
| k3s-control | k3s control-plane (API server, scheduler, etcd) | 1 | 4GB | Resized from 2GB after a capacity incident -- see Incidents below |
| k3s-worker | k3s worker node -- runs all cluster workloads | 2 | 6GB | Resized from 8GB; real usage is well under 2GB, so this still has headroom |
| ansible-control | Control node for Ansible and Terraform | 1 | 1GB | Where IaC is actually run from (see Tooling location) |
| it-docs | BookStack documentation wiki | 1 | 2GB | Build journal / runbook documentation |

## Repo layout

terraform/    Proxmox VM provisioning (main.tf, variables.tf, vault.tf)
ansible/      Configuration management playbooks and roles
k3s/          k3s cluster bootstrap (join scripts, kubeconfig handling)
k8s/          Kubernetes manifests and Helm values for workloads deployed to the cluster

## Tooling location

Terraform and Ansible both run from ansible-control (10.10.10.53). This is a deliberate consolidation -- Terraform originally ran from a separate Windows machine, and was moved onto this host to keep all infrastructure tooling in one place.

Required environment on ansible-control (already configured in ~/.bashrc):

export VAULT_ADDR=https://10.10.10.50:8200
export VAULT_CACERT=/home/shayan/homelab-infra/ansible/certs/vault-cert.crt

Terraform additionally needs, per session (deliberately never persisted to disk -- see Secrets):

export TF_VAR_vault_secret_id="<fresh AppRole SecretID>"

## Secrets

- terraform.tfvars (in terraform/) holds vault_role_id -- the Terraform AppRole's RoleID. Gitignored; not sensitive enough to warrant Vault storage itself, but kept out of version control on principle.
- vault_secret_id is never written to disk. Generate a fresh one per session:

  vault write -f auth/approle/role/terraform/secret-id
  export TF_VAR_vault_secret_id="<the returned secret_id>"

- The Proxmox API token itself is stored in Vault's KV engine (homelab/proxmox/terraform-token) and read by vault.tf at plan/apply time -- never hardcoded anywhere in this repo.

## Terraform state -- read before running Terraform on a new host

terraform.tfstate is gitignored and currently lives only as a local file on ansible-control. This is a known single point of failure, discovered the hard way: cloning this repo fresh onto a new host with no state file causes terraform plan to show all 5 VMs as new resources to create, because Terraform has no record that they already exist -- even though the config and the real infrastructure are identical.

Before running terraform plan/apply from any new host:
1. Copy terraform.tfstate (and terraform.tfstate.backup, if present) from ansible-control:~/homelab-infra/terraform/ to the new host, into the same relative path.
2. Copy terraform.tfvars the same way.
3. Run terraform init, then terraform plan -- it should report no changes. If it doesn't, stop and investigate before touching apply.

A proper remote backend (Vault-backed or otherwise) would eliminate this risk entirely and is a known follow-up, not yet implemented.

## What's running on k3s

Deployed via helm template -> vendored manifest -> kubectl apply --server-side (not helm install, so Helm's release/hook lifecycle isn't in play -- worth remembering when a chart ships install-time hooks).

- kube-prometheus (Prometheus, Grafana, kube-state-metrics, node-exporter) -- cluster and node metrics
- Loki + Alloy -- log aggregation and shipping
- Uptime Kuma -- external uptime/availability monitoring, 6 monitors configured

All pinned to k3s-worker via nodeSelector except DaemonSets (Alloy, node-exporter), which run on every node by design.

## Incidents

2026-09-23 -- k3s-control PLEG/API-server distress. After deploying and then tearing down Kyverno (a policy-as-code admission controller, evaluated and ultimately not kept in this build), k3s-control began failing PLEG health checks and timing out on API requests. Root cause: the Kyverno teardown left several ValidatingWebhookConfiguration/MutatingWebhookConfiguration objects registered, pointing at a service that no longer existed. Every matching API write attempted a doomed webhook call before timing out, and that repeated failure cycle manifested as sustained I/O wait and PLEG failure on the control plane. Removing the dangling webhook registrations resolved it immediately (load average dropped from ~3.5 to 0.2). k3s-control's RAM was subsequently resized from 2GB to 4GB as a deliberate resilience buffer, reallocating headroom from the over-provisioned k3s-worker, even though it wasn't the primary root cause.
