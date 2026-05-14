# AGENTS — Agent Role: PPM-READONLY

*Layer: `agent:ppm-readonly` · Synthesized 2026-05-14 by INSPR-179 Phase 4 · This layer holds 4 rules.*

This document is the authoritative source for the PPM read-only role (audit/discovery PPM agents). Other layers (read top-down for full context):

- **[AGENTS-CORE.md](./AGENTS-CORE.md)** — universal rules every agent follows
- **[AGENTS-PROFILE-MARKUS.md](./AGENTS-PROFILE-MARKUS.md)** — Markus Barta's personal preferences
- **AGENTS-AGENT-*.md** — per-role overlays (one per agent identity)
- **per-repo AGENTS.md** in nixcfg/fleetcom/inspr — repo-specific deltas

---

## Topic: workflow/ppm

- 🟡 **STRONG** | `always` | Always check for running timers before starting a new one
  *<sub>src: ~/Code/nixcfg/+agents/commands/ppm.md L73</sub>*
  <!-- rule_ids: ppm.md:L73:check-running-timers-before-start | cluster: — -->

- 🟡 **STRONG** | `do` | Stop timers when work is done
  *<sub>src: ~/Code/nixcfg/+agents/commands/ppm.md L74</sub>*
  <!-- rule_ids: ppm.md:L74:stop-timers-when-done | cluster: — -->


## Topic: agent-identity/ppm-readonly

- 🔴 **HARD** | `never` | In PPM mode, do not build, deploy, or provision anything
  *<sub>src: ~/Code/nixcfg/+agents/commands/ppm.md L10</sub>*
  <!-- rule_ids: ppm.md:L10:no-build-deploy-provision-ppm-mode | cluster: — -->

- 🔴 **HARD** | `never` | In PPM mode, do not modify local files, configs, or code unless user explicitly says "this is an exception"
  *<sub>src: ~/Code/nixcfg/+agents/commands/ppm.md L9</sub>*
  <!-- rule_ids: ppm.md:L9:no-modify-files-in-ppm-mode | cluster: — -->

