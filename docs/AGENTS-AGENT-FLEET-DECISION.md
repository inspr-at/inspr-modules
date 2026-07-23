# AGENTS — Agent Role: FLEET-DECISION

*Layer: `agent:fleet-decision` · Synthesized 2026-05-14 by INSPR-179 Phase 4 · This layer holds 10 rules.*

This document is the authoritative source for the FLEET-DECISION role (cross-fleet decision-making agents). Other layers (read top-down for full context):

- **[AGENTS-CORE.md](./AGENTS-CORE.md)** — universal rules every agent follows
- **[AGENTS-PROFILE-MARKUS.md](./AGENTS-PROFILE-MARKUS.md)** — Markus Barta's personal preferences
- **AGENTS-AGENT-*.md** — per-role overlays (one per agent identity)
- **per-repo AGENTS.md** in nixcfg/fleetcom/inspr/amt-com — repo-specific deltas

---

## Topic: agent-identity/contract

- 🔴 **HARD** | `always` | After an agent run, a fresh rebuild from main must reproduce the resulting state without the agent — otherwise the run violated Rule 1 even if it looked declarative
  *<sub>src: ~/Code/inspr/architecture.md L79</sub>*
  <!-- rule_ids: architecture.md:L79:reproducibility-test-after-agent-run | cluster: — -->

- 🔴 **HARD** | `always` | Agent drafts must be plain nix / plain YAML/JSON / plain Bosun verb invocations — not agent-internal blobs, serialized sessions, or vendor-specific DSL
  *<sub>src: ~/Code/inspr/architecture.md L106</sub>*
  <!-- rule_ids: architecture.md:L106:agent-draft-format-canonical | cluster: — -->

- 🔴 **HARD** | `never` | Agents must never imperatively bypass declarative — all fleet effects are either drafts of declarative artifacts or calls to typed Bosun verbs; ad-hoc ssh/manual edits forbidden
  *<sub>src: ~/Code/inspr/architecture.md L68-77</sub>*
  <!-- rule_ids: architecture.md:L75:agents-no-imperative-bypass-declarative | cluster: — -->

- 🔴 **HARD** | `always` | Every artifact the agent produces is in the same canonical format an expert would hand-author; hand-editing/skipping the agent are first-class paths, not fallbacks
  *<sub>src: ~/Code/inspr/architecture.md L89-93</sub>*
  <!-- rule_ids: architecture.md:L91:user-can-always-bypass-agent | cluster: — -->

- 🔴 **HARD** | `always` | Imperative bootstrap steps allowed ONLY when paired with self-retiring step that commits declarative version, verifies fresh rebuild reproduces, and deletes imperative artifact
  *<sub>src: ~/Code/inspr/architecture.md L81-87</sub>*
  <!-- rule_ids: architecture.md:L81:bootstrap-exception-self-retire | cluster: — -->

- 🔴 **HARD** | `never` | Never let one harness's vocabulary (e.g. Flue's Skills/Sessions/Sandboxes) shape the INSPR Agent Protocol — define from Paimos- and Pharos-native abstractions
  *<sub>src: ~/Code/inspr/architecture.md L59-60</sub>*
  <!-- rule_ids: architecture.md:L59:never-let-one-harness-shape-protocol | cluster: — -->

- 🔴 **HARD** | `always` | The Bosun verb set must be CLI-discoverable (--help, verbs list, man-style docs per verb), not just programmatic — expert override path depends on it
  *<sub>src: ~/Code/inspr/architecture.md L108-110</sub>*
  <!-- rule_ids: architecture.md:L108:bosun-cli-discoverable | cluster: — -->

- 🔴 **HARD** | `never` | There is no agent-only privileged channel; the agent's auth scope is always some subset of what a human user with that role could do at the CLI
  *<sub>src: ~/Code/inspr/architecture.md L93</sub>*
  <!-- rule_ids: architecture.md:L93:no-agent-only-privileged-channel | cluster: — -->

- 🟡 **STRONG** | `always` | Bosun verbs have typed schemas for inputs/outputs, --json by default; versioned under SemVer with adapters declaring target version
  *<sub>src: ~/Code/inspr/architecture.md L150-154</sub>*
  <!-- rule_ids: architecture.md:L150:bosun-typed-inputs-outputs | cluster: — -->

- 🟡 **STRONG** | `prefer` | Prove the INSPR Agent Protocol with two structurally-different consumers early (one Claude harness, one non-Claude exercising privacy/local-model path)
  *<sub>src: ~/Code/inspr/architecture.md L60</sub>*
  <!-- rule_ids: architecture.md:L60:prove-protocol-with-two-different-consumers | cluster: — -->
