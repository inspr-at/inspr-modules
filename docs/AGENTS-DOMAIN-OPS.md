# AGENTS — Domain: Ops

*Layer: `domain:ops` · INSPR-189 Phase 6 · Loaded on demand by `/ops`.*

Detailed rules for fleet ops, SSH, Tailscale/Headscale, host recovery, multi-session coordination. Kernel (auto-loaded) covers destructive-ops irreversibles and basic SSH user convention. This pack adds the access matrix, infra topology, recovery playbook.

**Load before**: cross-host work — SSH into fleet hosts, NixOS remote-builds, Tailscale/Headscale changes, routing decisions, multi-session handoffs. Pair with `/nix` for rebuild side, `/secrets` for credential changes.

---

## SSH access matrix

| Target                        | Command                                      | Notes                              |
| ----------------------------- | -------------------------------------------- | ---------------------------------- |
| Home LAN host                 | `ssh mba@<host>.lan`                         | hsb0, hsb1, hsb8, gpc0             |
| **imac0 exception**           | `ssh markus@imac0.lan`                       | user is `markus`, not `mba`        |
| Cloud server                  | `ssh mba@cs<n>.barta.cm -p 2222`             | csb0, csb1                         |
| Tailnet fallback              | `ssh mba@<host>.ts.barta.cm`                 | use when LAN doesn't route         |

- 🟡 Always use Tailscale (`*.ts.barta.cm`) when LAN access does not work — works from everywhere.
- 🟡 Reach internal hosts through the tailnet, not VPN concentrators, port-forwarding, public IP exposure, or SSH bastions.
- 🟢 Confirm with user before assuming Tailscale SSH is enabled vs classic SSH keys.

### `ssh_config` Match scoping

For local-user scope in `Match` blocks use `LocalUser` (or `LocalHost`/`OriginalHost`). Bare `User`/`Host` describe the connection **target**, not the local user running ssh. Easy to get backwards.

### NixOS programs.ssh wiring

NixOS `programs.ssh` client side does NOT include `/etc/ssh/ssh_config.d/*.conf`. Use `programs.ssh.extraConfig` for system-wide ssh-client `Match` blocks. Verify with `ssh -v`.

### macOS pubkey reads

On macOS, `/etc/ssh/*.pub` is world-readable — read pubkeys via plain `cat`, not `sudo`, to avoid Touch ID friction.

## Pattern: Tailscale / Headscale topology

- 🔴 Canonical Tailscale `--login-server`: `https://hs.barta.cm` (**service URL**). NEVER use the container host hostname `cs0.barta.cm` — it's the SSH/admin host, not the service.
- 🟡 On reverse-proxy fleets, distinguish host hostname (SSH/admin) from service hostname (clients) — ask which is needed if ambiguous.
- 🟡 `tailscale up` automation: always pass `--login-server` explicitly — macOS Tailscale daemon prefs do NOT reliably survive reboot.
- 🟡 Do NOT `sudo` the macOS Tailscale CLI — daemon runs as root via system extension; CLI talks via Unix socket as the regular user.
- 🟡 On macOS use the Tailscale `.app` CLI at `/Applications/Tailscale.app/Contents/MacOS/Tailscale`. NOT brew tailscale.
- 🟢 For Headscale on macOS, prefer standalone Tailscale.app variant (`brew cask tailscale-app`), not the App Store sandboxed version.
- 🟡 New machine joining the fleet must be enrolled in Headscale (preauth key, ACL/tag assignment) **before** it can reach anything.

## Pattern: fleet inventory

- 🟡 Query **FleetCom** (`fleet.barta.cm`) as the canonical live source for fleet inventory. Never assume static lists.
- 🟡 **msbp ownership migrated** (2026-05-02, INSPR-24 Stage 2). The host is alive and runs Percy/Percaival, but its NixOS config now lives in `BYTEPOETS/bpnixcfg` (not personal `nixcfg`). Route msbp config edits + Docker compose paths through `~/Code/BYTEPOETS/bpnixcfg/hosts/miniserver-bp/` on the workstation, or `~/Code/bpnixcfg/...` on the host itself. Tickets for msbp belong in PMO/**BPOPS26** (epic BPOPS26-99), not personal PPM/NIX.

## Pattern: host recovery

### Post-reboot health

SSH-back is necessary but not sufficient. Build a routine that waits for:
- SSH responsive
- ICMP responsive
- Expected `systemd` targets `active`
- Expected container count

Don't declare a host healthy on SSH alone.

### Trust-modifying infra rollouts

- 🔴 Design new mechanism to be **ADDITIVE alongside the old one** — never remove a key during rollout, only add. Prevents lockout.
- 🔴 `command='...'`-restricted SSH keys MUST be preserved verbatim through any keyring abstraction (`extraKeys` raw-passthrough). Abstracting strips restrictions.
- 🟡 For auth-touching infra changes, keep a live root/sudo session open as recovery channel throughout — use it only for recovery, not for the change.
- 🟡 Keep `PasswordAuthentication=true` on csb0/csb1 until per-host ed25519 keys deployed AND validated AND legacy RSA retired (defence-in-depth).

### SSH key inventory hygiene

- 🔴 Never delete a key from a host without confirming it's not the only admittance — grep first, then ask.
- 🔴 Never reuse an alias for a different key. New RSA replacement → new alias (`markus-rsa-2026`), not re-binding.
- 🟡 Never assume the admittance inventory is complete — always re-grep before retiring.
- 🟡 For fleet-scale host-key trust, treat the longest-running and most-trusted workstation as authoritative; cross-reference before adding keys elsewhere.
- 🔴 Never read any `~/.ssh/` file lacking the `.pub` extension.

## Pattern: stuck NixOS rebuild

- 🔴 **Never** `systemctl stop nixos-rebuild-switch-to-configuration.service` on the "already loaded" error. Wait for `is-active inactive` or use `systemctl reset-failed`. (NIX-101.)
- 🟡 When automation seems stuck, investigate via `systemctl status` + `journalctl` BEFORE force-killing. Operator-induced fix attempts often cause more damage than the original problem.
- 🟡 Before assuming an infrastructure surprise is a real bug, gather concrete journal evidence (timestamps, systemd state transitions, operator commands intervened).

See `/nix` for full NixOS build-safety details.

## Pattern: long-running ops commands

- 🟡 Background or zellij session for long jobs. Prefix commands >10s with `date &&` (bash) or `date; and` (fish). Use `run_in_background` for >30s nix builds / docker pulls.

## Pattern: multi-session coordination

- 🟡 **Codify-and-hand-off beats turn-taking.** When waiting for another session, write a self-contained ticket (code/diffs/validation gates/rollback) and hand off — let the other session execute as a batch.
- 🟡 Treat unrecognized changes as another agent's work; keep going on your scope. If it causes issues, stop and ask.
- 🟡 Multi-agent repos with not-yours dirt: `git stash push -- <paths>`, work, pop. Don't `git stash` everything.

## Pattern: probe behavior, not just status

- 🟡 Validate probe responses by examining body and headers, not just status code. Healthchecks must assert on response **content**.
- 🟡 Test URLs by probing for protocol-shaped responses (e.g. Tailscale-shaped JSON).
- 🟡 Onboarding tooling must always distinguish host and service URL explicitly in setup forms; never let one default-fill into the other.
- 🟡 For security-restricted dirs, probe what unprivileged code can actually prove (`[ -d $dir ]`); don't try to inspect what's intentionally hidden.

## Pattern: dual-config surface warnings

Tools with both legacy non-XDG and XDG config locations: declarative config managers should warn loudly when both files exist on the same host (canonical: legacy `~/.gitconfig` shadowing HM-managed `~/.config/git/config`).

## Pattern: pacing for interactive ops

Kernel rule: ONE step at a time during interactive procedures, wait for explicit "done". Keep a private todo list, only show the user the current step.

## Pattern: pre-flight on auth-touching changes

- 🔴 Agent ships reversible changes without asking; pauses and explicitly asks before destructive ops (`--rekey`, `nixos-rebuild switch` on critical services, secret material).
- 🟡 For multi-host trust changes, work the additive-rollout discipline (above) and verify with the new path before retiring the old.

---

*See also*: `/nix` (rebuild safety, activation DAG), `/secrets` (AGE rekey hygiene during fleet ops), `/dev` (git in multi-session coordination). Full source: `AGENTS-CORE.md` topics `tools/ssh`, `infra/{tailscale,fleet-state}`, `security/{ssh-keys,destructive-ops}`, `process/{host-recovery,rollout-discipline,onboarding}`, `workflow/agent-handoff`, `pacing/interactive`.*
