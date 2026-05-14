# AGENTS — Agent Role: OPENCLAW-OPS

*Layer: `agent:openclaw-ops` · Synthesized 2026-05-14 by INSPR-179 Phase 4 · This layer holds 12 rules.*

This document is the authoritative source for the OPENCLAW-OPS role (Open Clearance Workspace operations). Other layers (read top-down for full context):

- **[AGENTS-CORE.md](./AGENTS-CORE.md)** — universal rules every agent follows
- **[AGENTS-PROFILE-MARKUS.md](./AGENTS-PROFILE-MARKUS.md)** — Markus Barta's personal preferences
- **AGENTS-AGENT-*.md** — per-role overlays (one per agent identity)
- **per-repo AGENTS.md** in nixcfg/fleetcom/inspr — repo-specific deltas

---

## Topic: secrets/agenix-pipeline

- 🔴 **HARD** | `never` | OpenClaw secrets must go through agenix; never plaintext in configs
  *<sub>src: ~/Code/nixcfg/+agents/commands/ocbots.md L146</sub>*
  <!-- rule_ids: ocbots.md:L146:secrets-agenix-only | cluster: — -->


## Topic: process/sync-triad

- 🔴 **HARD** | `always` | modelhelp SKILL.md in all 3 workspace repos must stay in sync with openclaw.json
  *<sub>src: ~/Code/nixcfg/+agents/commands/oc-modelupdate.md L143</sub>*
  <!-- rule_ids: oc-modelupdate.md:L143:modelhelp-skill-md-in-sync-3-repos | cluster: — -->


## Topic: pacing/long-running

- 🔴 **HARD** | `do` | Long ops (rebuilds): provide commands only; Markus runs them; state time estimate
  *<sub>src: ~/Code/nixcfg/+agents/commands/ocbots.md L148</sub>*
  <!-- rule_ids: ocbots.md:L148:long-ops-handoff-state-eta | cluster: — -->


## Topic: nixos/build-safety

- 🔴 **HARD** | `never` | All OpenClaw config changes go through nixcfg; never edit directly on hosts
  *<sub>src: ~/Code/nixcfg/+agents/commands/ocbots.md L145</sub>*
  <!-- rule_ids: ocbots.md:L145:nixcfg-only-no-direct-edits | cluster: — -->


## Topic: agent-identity/openclaw-ops

- 🔴 **HARD** | `always` | Both openclaw.json configs must stay in sync — always edit both
  *<sub>src: ~/Code/nixcfg/+agents/commands/oc-modelupdate.md L142</sub>*
  <!-- rule_ids: oc-modelupdate.md:L142:both-openclaw-configs-stay-in-sync | cluster: — -->

- 🔴 **HARD** | `never` | Do not commit without user saying "OK to apply"
  *<sub>src: ~/Code/nixcfg/+agents/commands/oc-modelupdate.md L140</sub>*
  <!-- rule_ids: oc-modelupdate.md:L140:no-commit-without-ok | cluster: — -->

- 🔴 **HARD** | `never` | Do not invent model IDs; only use IDs confirmed in the live OpenRouter catalogue
  *<sub>src: ~/Code/nixcfg/+agents/commands/oc-modelupdate.md L48</sub>*
  <!-- rule_ids: oc-modelupdate.md:L48:no-invent-model-ids | cluster: — -->

- 🔴 **HARD** | `never` | Do not touch the fallback or primary model without explicit approval
  *<sub>src: ~/Code/nixcfg/+agents/commands/oc-modelupdate.md L139</sub>*
  <!-- rule_ids: oc-modelupdate.md:L139:no-touch-fallback-without-approval | cluster: — -->

- 🔴 **HARD** | `always` | HIL protocol: propose before any state change; hsb0 is Crown Jewel (DNS/DHCP)
  *<sub>src: ~/Code/nixcfg/+agents/commands/ocbots.md L149</sub>*
  <!-- rule_ids: ocbots.md:L149:hil-propose-before-state-change | cluster: — -->

- 🔴 **HARD** | `always` | In /oc-modelupdate, present findings to user BEFORE making any changes; ask OK to apply
  *<sub>src: ~/Code/nixcfg/+agents/commands/oc-modelupdate.md L69-79</sub>*
  <!-- rule_ids: oc-modelupdate.md:L78:present-summary-before-changes | cluster: — -->

- 🟡 **STRONG** | `always` | Before any oc-rebuild or percy-rebuild, check the OpenClaw changelog for breaking changes
  *<sub>src: ~/Code/nixcfg/+agents/commands/ocbots.md L76</sub>*
  <!-- rule_ids: ocbots.md:L76:check-changelog-before-rebuild | cluster: — -->

- 🟡 **STRONG** | `always` | In /ocbots context read the OpenClaw runbooks carefully — they are the source of truth
  *<sub>src: ~/Code/nixcfg/+agents/commands/ocbots.md L19</sub>*
  <!-- rule_ids: ocbots.md:L19:read-runbooks-source-of-truth | cluster: — -->

