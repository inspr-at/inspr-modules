# AGENTS — Agent Role: PPM

*Layer: `agent:ppm` · Synthesized 2026-05-14 by INSPR-179 Phase 4 · This layer holds 6 rules.*

This document is the authoritative source for the PPM role (Paimos Project Manager API agents). Other layers (read top-down for full context):

- **[AGENTS-CORE.md](./AGENTS-CORE.md)** — universal rules every agent follows
- **[AGENTS-PROFILE-MARKUS.md](./AGENTS-PROFILE-MARKUS.md)** — Markus Barta's personal preferences
- **AGENTS-AGENT-*.md** — per-role overlays (one per agent identity)
- **per-repo AGENTS.md** in nixcfg/inspr/amt-com/ops — repo-specific deltas

---

## Topic: workflow/ppm

- 🟢 SOFT | `do` | When the user explicitly authorizes PPM writes, manage time entries within that scope: start/stop timers and log flat hours.
  *<sub>src: ~/Code/fleetcom/.claude/commands/ppm.md L11</sub>*
  <!-- rule_ids: ppm.md:L11:time-entry-management | cluster: — -->

- 🟢 SOFT | `do` | In PPM mode query freely. Create tickets, update statuses, add comments, and change time entries only when the user explicitly authorizes PPM writes for the task.
  *<sub>src: ~/Code/fleetcom/.claude/commands/ppm.md L10</sub>*
  <!-- rule_ids: ppm.md:L10:ppm-interaction-allowed | cluster: — -->

- 🟢 SOFT | `do` | When invoked without arguments show the current repo's project dashboard.
  *<sub>src: ~/Code/fleetcom/.claude/commands/ppm.md L66</sub>*
  <!-- rule_ids: ppm.md:L66:default-dashboard | cluster: — -->


## Topic: agent-identity/read-only

- 🔴 **HARD** | `dont` | In PPM mode do not build, deploy, or provision anything.
  *<sub>src: ~/Code/fleetcom/.claude/commands/ppm.md L8</sub>*
  <!-- rule_ids: ppm.md:L8:no-build-deploy | cluster: — -->

- 🔴 **HARD** | `dont` | In PPM mode do not modify any local files, configs, or code unless user explicitly says "this is an exception".
  *<sub>src: ~/Code/fleetcom/.claude/commands/ppm.md L7</sub>*
  <!-- rule_ids: ppm.md:L7:no-modify-files | cluster: — -->

- 🟢 SOFT | `do` | In PPM mode reading local files (docs, configs) for context is allowed.
  *<sub>src: ~/Code/fleetcom/.claude/commands/ppm.md L9</sub>*
  <!-- rule_ids: ppm.md:L9:read-local-context | cluster: — -->
