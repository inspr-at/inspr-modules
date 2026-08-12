# AGENTS — Domain: Ops

*Layer: `domain:ops` · INSPR-189 Phase 6 · Loaded on demand by `/ops`.*

Detailed rules for fleet ops, SSH, Tailscale/Headscale, host recovery, multi-session coordination. Kernel (auto-loaded) covers destructive-ops irreversibles and basic SSH user convention. This pack adds the access matrix, infra topology, recovery playbook.

**Load before**: cross-host work — SSH into fleet hosts, NixOS remote-builds, Tailscale/Headscale changes, routing decisions, multi-session handoffs. Pair with `/nix` for rebuild side, `/secrets` for credential changes.

---

## SSH access matrix

| Target          | Command                          | Notes                          |
| --------------- | -------------------------------- | ------------------------------ |
| Home LAN host   | `ssh mba@<host>.lan`             | hsb0, hsb1, hsb8, hsb9         |
| Cloud server    | `ssh mba@cs<n>.barta.cm -p 2222` | csb0, csb1                     |
| Tailnet         | `ssh mba@<tailnet-ip>`           | **IP, not name** — see below   |

### 🔴 MagicDNS is permanently OFF — `*.ts.barta.cm` does NOT resolve

Markus disabled MagicDNS deliberately and indefinitely: it was breaking agent sessions. Any `<host>.ts.barta.cm` name will fail with `nodename nor servname provided`. **This is expected, not an outage — do not debug it, do not try to "fix" DNS, and do not report the tailnet as down.**

Reach tailnet hosts by **IP**. Get the current IP from the local Tailscale CLI — never hardcode one, and never assume a static list:

```sh
/Applications/Tailscale.app/Contents/MacOS/Tailscale status   # macOS
tailscale status                                              # Linux
ssh -p 2222 mba@100.64.0.4                                    # e.g. csb1
```

`tailscale status` is also the fastest way to see whether a host is actually alive — it reports `offline, last seen …` for retired or dead nodes.

- 🟡 Reach internal hosts through the tailnet, not VPN concentrators, port-forwarding, public IP exposure, or SSH bastions.
- 🟡 Cloud servers keep their non-standard port on the tailnet too: `-p 2222` for csb0 / csb1.
- 🟡 A retired host can linger as a tailnet node long after its config is gone — removing it from Headscale is a separate teardown step.
- 🟢 Confirm with user before assuming Tailscale SSH is enabled vs classic SSH keys.
- ⚠️ **imac0 / imacw are decommissioned** (OPS guideline `imac-fleet-decommissioned`) and **gpc0 was retired 2026-07 → stm2607**. None of them are reachable; don't route work to them.

### `ssh_config` Match scoping

For local-user scope in `Match` blocks use `LocalUser` (or `LocalHost`/`OriginalHost`). Bare `User`/`Host` describe the connection **target**, not the local user running ssh. Easy to get backwards.

### NixOS programs.ssh wiring

NixOS `programs.ssh` client side does NOT include `/etc/ssh/ssh_config.d/*.conf`. Use `programs.ssh.extraConfig` for system-wide ssh-client `Match` blocks. Verify with `ssh -v`.

### macOS pubkey reads

On macOS, `/etc/ssh/*.pub` is world-readable — read pubkeys via plain `cat`, not `sudo`, to avoid Touch ID friction.

## Pattern: Tailscale / Headscale topology

- 🔴 **MagicDNS is permanently disabled** (it broke agent sessions). `*.ts.barta.cm` does not resolve — address tailnet hosts by IP from `tailscale status`. See the SSH access matrix above.
- 🔴 Canonical Tailscale `--login-server`: `https://hs.barta.cm` (**service URL**). NEVER use the container host hostname `cs0.barta.cm` — it's the SSH/admin host, not the service.
- 🟡 On reverse-proxy fleets, distinguish host hostname (SSH/admin) from service hostname (clients) — ask which is needed if ambiguous.
- 🟡 `tailscale up` automation: always pass `--login-server` explicitly — macOS Tailscale daemon prefs do NOT reliably survive reboot.
- 🟡 Do NOT `sudo` the macOS Tailscale CLI — daemon runs as root via system extension; CLI talks via Unix socket as the regular user.
- 🟡 On macOS use the Tailscale `.app` CLI at `/Applications/Tailscale.app/Contents/MacOS/Tailscale`. NOT brew tailscale.
- 🟢 For Headscale on macOS, prefer standalone Tailscale.app variant (`brew cask tailscale-app`), not the App Store sandboxed version.
- 🟡 New machine joining the fleet must be enrolled in Headscale (preauth key, ACL/tag assignment) **before** it can reach anything.

## Pattern: fleet inventory

- 🟡 Query **Pharos** (<https://pharos.barta.cm> — `pharosd` on csb1) as the canonical live source for fleet inventory; HostDash renders the same data for humans. Never assume static lists. FleetCom is archived — never query `fleet.barta.cm`.
- 🟡 **msbp is gone.** It left with the June 2026 employer exit — not our host, not our config, not our tickets. Its config lived in the former work flake and its tickets in PMO/BPOPS26; both are out of scope. Don't route work there, and don't expect it in fleet inventory.

## Pattern: host-local service credentials

Fleet services (Home Assistant, MQTT brokers, cameras, …) authenticate with per-host tokens that are **agenix-managed on the host itself** — `/run/agenix/<host>-<service>-env` — and never mirrored to the workstation. The workstation convention (`~/.inspr/secrets/agents/<NAME>.env`, INSPR-164) covers only agent-scoped tokens: **an empty agents dir does NOT mean no access path exists.** (INSPR-294.)

- 🟡 Use the credential **on the host**, so the value never leaves it and never enters the transcript:

  ```sh
  ssh mba@<host>.lan "bash -c '( set -a; source /run/agenix/<host>-<service>-env; set +a; <cmd using \$VAR> )'"
  ```

- 🟡 Which file carries which credential: the host's PPM runbook entry (`paimos knowledge get runbook host-<name> --project OPS`) is canonical; long-form reference in `nixcfg hosts/<host>/docs/`. Example: the Home Assistant LLAT is `/run/secrets/hass-token` inside the OpenClaw containers on **hsb0** (agenix `hsb0-openclaw-hass-token`), used cross-host against HA on hsb1.
- 🟡 The credential lives with its **consumer**, which may be a different host than the service — the HA token sits on hsb0 (OpenClaw consumes it), not on hsb1 where HA runs. Grep the agenix inventory (`nixcfg secrets/*.age` file *names*) before concluding no credential exists.
- 🟡 Repo docs go stale — verify a documented credential location (names-only env check, or a live call) before relying on it or re-documenting it. Precedent: SMARTHOME.md claimed a `HASS_TOKEN` that did not exist (NIX-355).
- 🔴 Kernel secret rules apply unchanged: never `cat`/read the env file, never echo the variable — source-and-use only (in-container `$(cat …)` feeding a header, or subshell `source`, never output).

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
