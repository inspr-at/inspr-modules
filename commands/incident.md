# /incident — Incident response protocol

Load incident-response context for security incidents, secret leaks, lockout recovery, and host emergencies.

@./doctrine/docs/AGENTS-DOMAIN-SECRETS.md

You are now operating with INCIDENT-RESPONSE context. The kernel already covers the immediate stop conditions (STOP on secret-in-output, alert user, rotate). This pack adds:

## Secret-leak protocol (canonical)

1. **STOP** the current command pipeline immediately. Do not run further commands that touch the same secret pipeline.
2. **Do NOT reference, repeat, or quote** the secret value in any output, comment, or follow-up message. Name the AFFECTED VARIABLES to the user, but never the values.
3. **Treat as compromised by default.** If the transcript ever left the local machine (sent to cloud, shared, uploaded), prefer immediate rotation over containment.
4. **Rotate every exposed credential** before continuing. Use canonical rotation flow (1P → update env file → `agenix --rekey` if .age-backed → service restart).
5. **Update the leak inventory** in `~/Code/inspr/playbook.md` Day-N section (incident log).

## Lockout recovery

- For NixOS rebuild lockouts: keep PasswordAuthentication=true on csb0/csb1/msbp until per-host ed25519 keys deployed AND validated AND legacy RSA fully retired (defence-in-depth)
- Keep a live root/sudo session open as recovery channel during any auth-touching change — use ONLY for recovery, not for the change itself
- For HM/NixOS activation failure, verify (a) login shell still execable, (b) PATH binaries present, (c) SSH still functional, (d) home-manager itself still in profile

## Host recovery

- SSH-back is necessary but not sufficient post-reboot; build a routine that waits for SSH + ICMP + expected systemd targets active + expected container count
- When automation seems stuck, investigate via `systemctl status` + `journalctl` BEFORE force-killing; operator-induced fix attempts often cause more damage than the original problem

## Encrypted-file corruption

- If `agenix --rekey` produced 578-byte files (header-only, content wiped): STOP — do not commit or push; restore via `git reset --hard`
- If encrypted file is corrupted and you can't restore: alert user, guide restore from git, rotate the credential

Cross-references on demand:

- `/secrets` — full secrets pipeline depth
- `/ops` — SSH matrix, host inventory, recovery routes

For the comprehensive rule reference, see `inspr-modules/docs/AGENTS-CORE.md` topics `incident-response/secret-leak`, `process/host-recovery`, `process/lockout-recovery`.
