# Okta SSO federation: four apps, four mechanisms

*Part of [homelab-infra](../README.md).*

**In one sentence:** Grafana, BookStack, Gitea and Vault all authenticate through one Okta org, each integrated a different way, with access and roles driven by two shared Okta groups.

## Why this exists

In an enterprise, applications delegate login to a central identity provider, so access is granted, changed and revoked in one place. Group membership in the IdP then decides what each person can do inside each app. This lab simulates that with Okta (Integrator Free Plan) as the workforce identity provider and OpenID Connect (Authorization Code flow) as the protocol.

## Design at a glance

- **Two shared groups** (`homelab-admins`, `homelab-viewers`) are used by every app instead of one-off per-app groups, so access is controlled by membership in one place.
- **A scoped `groups` claim** on Okta's default authorization server is filtered by regex to `homelab-.*`, so tokens carry only the two lab groups and not Okta's built-in ones.
- **A client-scoped access policy per app,** with an Authorization Code rule. A fresh Okta authorization server has no policy rules at all, so every login fails until one exists.
- **Secrets stay out of git.** Each app's client ID, client secret and issuer live in Vault under `homelab/okta/<app>` and are read by Ansible at deploy time. Only templates are tracked.
- **Config lives in files, not UIs.** Grafana has a built-in Okta settings page; I configured it through version-controlled config instead, so the setup survives a pod rebuild and shows up in git history.

*The two shared groups in the Okta directory:*

<img width="1266" height="570" alt="image" src="https://github.com/user-attachments/assets/87f13d3e-e066-4ea3-a980-e0cc4314cc99" />


## The four mechanisms

*The four Okta application registrations (client IDs redacted):*

<img width="2104" height="1048" alt="apps" src="https://github.com/user-attachments/assets/97213ac3-3f8d-40c3-8d24-762baa89a6b4" />


| App | How it is wired | Group-to-role mapping | Notes |
|---|---|---|---|
| Grafana | `grafana.ini` settings delivered as a Kubernetes Secret rendered by an Ansible role, layered on the vendored manifests with Kustomize | A JMESPath expression (`role_attribute_path`) evaluated against the `groups` claim | Local login kept as break-glass |
| BookStack | Environment variables in the Docker Compose template, using OIDC auto-discovery | Literal, case-insensitive matching between group names and BookStack role names (roles named `homelab-admins` and `homelab-viewers`) | OIDC replaces local login entirely |
| Gitea | OAuth source defined in Helm chart values and stored in Gitea's own database, not in a config file | Built-in tiers: admin group becomes administrator, restricted group is restricted, everyone else is a regular user | Additive: local login still works |
| Vault | Vault's native `auth/oidc` method, separate from app-level config | Okta group bound in a Vault OIDC role, which maps to an ACL policy | Admin-only, no viewer tier |

## Design decisions and trade-offs

- **Vault has no viewer tier.** Any authenticated Vault session carries risk whatever ACL policy it holds, so only `homelab-admins` can even attempt login. This is a deliberate departure from the admin/viewer split used in the other three apps.
- **Human and machine identity are separate.** The human admin policy is distinct from the read-only policy Ansible's AppRole uses. The admin policy denies seal, rekey, raw storage, root generation and edits to the root policy, grants no delete or destroy capability, and its OIDC role issues tokens with a 1 hour TTL (4 hour max).
- **Authorization structure is version-controlled.** Vault policies and OIDC role definitions live in `vault/policies/` and `vault/roles/`. They describe paths and group bindings, not secrets. The auth backend config and Okta app registrations are not stored there.
- **BookStack gives up local login.** Stable BookStack cannot run OIDC alongside local passwords. I accepted that for a low-risk internal wiki; the recovery path is to revert one setting in the Compose file and redeploy.
- **Two apps are deliberately not federated.** Uptime Kuma has no native OIDC (single user only), and a proxy sidecar would add attack surface with no role mapping. Vaultwarden derives its encryption key client-side from the master password, which is incompatible with federation that grants access by login.

## Problems hit and fixed

| Symptom | Root cause | Fix |
|---|---|---|
| `access_denied` / "Policy evaluation failed" with a correct app config | A fresh default authorization server ships with no access policy rules | A client-scoped access policy with an Authorization Code rule, per app |
| `invalid_scope` (Grafana, then again in BookStack) | `groups` was requested as a scope, but it is a claim | Removed it from the requested scopes; kept the claim-reading config |
| Grafana redirected to `localhost:3000` after login | `root_url` was unset | Set `root_url` in the server section |
| Grafana stuck on restart | A ReadWriteOnce volume plus a rolling update left two pods contending for it | `Recreate` strategy, persisted in the Kustomize patch |
| Gitea Helm error, then a wrong URL scheme | `gitea.oauth` must be a list (the chart supports multiple providers) and `ROOT_URL` was http | List format; https |
| Vault OIDC login failing | The redirect URI host registered in Okta differed from the hostname Vault actually served, a naming drift from an earlier DNS decision | Corrected in Okta and the Vault role, confirmed against the certificate's SAN |
| Vault CLI OIDC login hanging over SSH | The browser and the local callback listener must be on the same machine | Used the UI login flow |
| New Vault auth method missing from the UI login dropdown | New auth methods are hidden by default | Set the method's listing visibility to `unauth` |

## What was verified

Each check below was done by signing in through Okta and reading the resulting role inside the app.

### Grafana: both branches of the role mapping

A user in `homelab-admins` lands as Admin. A second Okta user placed only in `homelab-viewers` lands as Viewer. Both show the "Generic OAuth" origin, and their role controls are greyed out because the role comes from the group mapping.

*Login page: Okta sign-in next to the local break-glass form:*

<img width="806" height="948" alt="image" src="https://github.com/user-attachments/assets/0ffd83a6-cb12-4eae-ac95-9e239f2f6ea0" />


*Users list: one Okta admin and one Okta viewer-only user, emails redacted:*

<img width="2354" height="825" alt="grafana users" src="https://github.com/user-attachments/assets/76682c19-d9a6-437f-9669-36f4dec2b8ea" />


### BookStack: group membership becomes a BookStack role

*The Okta-created user holds the `homelab-admins` role:*

<img width="808" height="325" alt="image" src="https://github.com/user-attachments/assets/897967b2-5bf9-467e-ba64-229865e74309" />


<img width="1419" height="932" alt="bookstack users" src="https://github.com/user-attachments/assets/fcb15f03-05d1-4c02-b47b-e057a4ad8752" />



### Gitea: admin group becomes Site Administration

An Okta login from `homelab-admins` grants Site Administration.

*User menu showing Site Administration after an Okta login:*

<img width="794" height="649" alt="image" src="https://github.com/user-attachments/assets/77014a02-1066-4585-8032-68f7e531764a" />


<img width="1211" height="259" alt="gitea login" src="https://github.com/user-attachments/assets/981aa851-4ca8-43f5-8871-b2be4d47abfa" />



### Vault: native OIDC method alongside AppRole

An Okta login through the UI succeeds with the admin policy attached.

*Vault's auth methods: `oidc/` for humans, `approle/` for Terraform and Ansible:*


<img width="1412" height="978" alt="image" src="https://github.com/user-attachments/assets/ce5ba26f-240b-4236-9b67-a91fe7f8e494" />



<img width="1412" height="689" alt="otka auth methods" src="https://github.com/user-attachments/assets/a5b06cfe-ec0e-492c-b3e9-a10642adfcc3" />


## Limitations and what an enterprise would do differently

- **The Okta org is configured by hand in the console.** An enterprise would manage it as code with the Terraform Okta provider. Vault's auth backend was also set up by hand through the CLI; moving it to Terraform is planned.
- **Group membership is managed manually.** Enterprise rollouts tie it to HR-driven joiner/mover/leaver lifecycle (SCIM) and add MFA and conditional-access policy. This page covers none of that.
- **One identity provider is a single point of failure.** Break-glass paths exist: local logins for Grafana and Gitea, the Vault root token and unseal keys stored outside Vault, and a config revert for BookStack.
- **Internal PKI:** certificates come from a self-signed root CA, so each client must trust that root. Okta requires HTTPS redirect URIs, which is why cert-manager exists in this build.
