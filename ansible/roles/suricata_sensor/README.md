# suricata_sensor

Configures the Suricata IDS sensor on the Raspberry Pi (raspi, group
raspberry_pi): packages, persistent passive capture on eth1, HOME_NET and
af-packet interface, ET Open rules, config validation, and a staged (not
applied) Wazuh localfile snippet.

Run: export ANSIBLE_VAULT_SECRET_ID, then
ansible-playbook playbooks/suricata-sensor.yml
Variables: inventory/group_vars/raspberry_pi.yml (suricata_*). This role
needs no Vault secrets. Unlike the pihole role it ships templates/ and
files/ (capture unit, NetworkManager file, Wazuh snippet).

## Design notes
- Packages are state=present, not latest, so the sensor does not upgrade
  itself as a side effect of a run.
- suricata-update always exits 0, so change detection keys on its
  "No changes detected" message. That wording is version-specific.
- enable-source prints "enabled" even when the source already was, so it is
  guarded by list-enabled-sources.
- suricata -T runs in the task list before any handler, so a broken config
  fails the run before the restart and the live sensor keeps its old config.
- The eth1 no-IP and unmanaged checks are read-only asserts: they fail the
  run on drift instead of repairing it, so drift gets noticed.

## Limitations (honest list)
- eth1 persistence (NetworkManager unmanaged file + capture unit) is NOT
  reboot-tested. The Pi is the LAN's DNS server.
- Only the converged path was exercised. The fresh-install path (stopping the
  package-started instance, first rule download, first restart) and the
  NetworkManager reload handler have not been run.
- --check skips enable-source and suricata-update (they download and write
  files), and the read/assert tasks are skipped too, so changed=0 in check
  mode says nothing about rules or the asserts.
- Every rules update restarts Suricata (capture gap while ~69k rules load on
  a Pi). The unit has ExecReload, but the suricatasc socket was not verified,
  so live reload is not used.
- Only the HOME_NET and af-packet lines of suricata.yaml are managed. Other
  drift is invisible, and a package upgrade may raise a dpkg conffile prompt
  for that file (untested).
- The config asserts depend on the --dump-config output format observed on
  Suricata 7.0.10.
- No scheduled rule updates: rules change only when the playbook runs.
- Visibility is limited by the SG108E, which mirrors one source port at a
  time (raspi by default). Traffic that never crosses that port, including
  PVE-to-raspi local traffic, is invisible.
- ET Open only, no rule tuning or thresholds. Alerts are not forwarded: Wazuh
  is not built and the snippet is only staged.
- Logs are on the SD card, rotated weekly with 14 rotations.
- Single sensor, no HA. admin has NOPASSWD sudo; production would use a
  dedicated service account.
- The Wazuh staging dir and file modes (0775/0664) match the live Pi but are
  group-writable, which is not hardened.
