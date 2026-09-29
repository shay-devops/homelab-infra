# pihole role

Manages the configuration of an already-installed Pi-hole v6 on `raspi`.
Pi-hole itself is installed by hand with the official installer (defaults, interface eth0).

## What it manages
- Five pihole-FTL settings (upstreams, revServers, piholePTR, interface, web theme),
  compared with `pihole-FTL --config` and written only when different.
- Admin password from Vault (`homelab/raspi/pihole`, key `password`), reset only when the
  API rejects it. Fails early if the value is shorter than 8 characters, because an empty
  value would remove dashboard authentication.
- NetworkManager DNS override on eth0 (ignore DHCP DNS, use the FortiGate).
- Restarts pihole-FTL via handler, only when a setting changed.

## Prerequisites (manual bootstrap)
- Pi-hole installed with the official installer; SSH key auth for user `admin`;
  passwordless sudo rule for `admin` (lab choice; production would use a dedicated
  service account).
- Vault secret `homelab/raspi/pihole` and an `ansible-policy` read stanza for
  `homelab/data/raspi/*`.
- `ANSIBLE_VAULT_SECRET_ID` set in the shell before running.

## Run
    ansible-playbook playbooks/pihole.yml [--check --diff]

## Known limitations
- Install is not automated. The installer's `--unattended` flag still shows dialogs on a fresh
  install unless a config file is pre-seeded; that route is untested.
- Verified: dry run and live run against the converged Pi report changed=0.
  Not exercised: the apply-setting path, the restart handler, the password reset, and a
  changed NetworkManager override.
- `pihole setpassword` takes the password as a command-line argument, so it is briefly visible
  in the process list while that task runs.
