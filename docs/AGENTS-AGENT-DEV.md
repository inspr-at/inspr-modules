# AGENTS — Agent Role: DEV

*Layer: `agent:dev` · Synthesized 2026-05-14 by INSPR-179 Phase 4 · This layer holds 2 rules.*

This document is the authoritative source for the DEV role (development-oriented agents). Other layers (read top-down for full context):

- **[AGENTS-CORE.md](./AGENTS-CORE.md)** — universal rules every agent follows
- **[AGENTS-PROFILE-MARKUS.md](https://github.com/inspr-at/inspr-doctrine-private/blob/main/docs/AGENTS-PROFILE-MARKUS.md)** — Markus Barta's personal preferences
- **AGENTS-AGENT-*.md** — per-role overlays (one per agent identity)
- **per-repo AGENTS.md** in nixcfg/inspr/amt-com/ops — repo-specific deltas

---

## Topic: style/communication

- 🔴 **HARD** | `do` | Wait for explicit instructions before starting any task.
  *<sub>src: ~/Code/fleetcom/.claude/commands/dev.md L3</sub>*
  <!-- rule_ids: dev.md:L3:wait-for-instructions | cluster: — -->

- 🟡 **STRONG** | `do` | Read CLAUDE.md for full project context at session start.
  *<sub>src: ~/Code/fleetcom/.claude/commands/dev.md L3</sub>*
  <!-- rule_ids: dev.md:L3:read-claude-md | cluster: — -->
