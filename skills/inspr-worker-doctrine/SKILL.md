---
name: inspr-worker-doctrine
description: "Mandatory INSPR worker-start and versioning doctrine. Read before material work, worker delegation, project bootstrap, and every release or deployment."
---

# INSPR Worker Doctrine

This installed surface carries the canonical worker contracts from the same
immutable `inspr-modules` revision as this skill. Read both references before
material work or versioning decisions:

- [Worker attribution](references/AGENTS.md): choose the product's designated
  PPM or PMA tracker, never both, and record the canonical value-free
  `I work on this — session: <session-name> (<session-UUID>); role: <builder|reviewer|operator>; started: <ISO-8601>`
  marker before any participating worker makes a state change.
- [Versioning doctrine](references/AGENTS-VERSIONING.md):
  `YYMMDDhhmmss.0.0` (`inspr-calendar-v2`, SemVer-syntactic, fixed-width)
  is the gradual INSPR default; `YY.MM.DD[.hh.mm.ss]` (v1) is superseded.
  Every repository remains on its current scheme until its own approved
  migration is complete.
  At project bootstrap and before every release/deployment, apply the
  adoption outcomes in that reference: new-project default; existing adoption
  ticket with the next deployment; absent ticket requires an explicit standard
  proposal; adopted projects review the current saved presentation pin.
  Record the outcome in the owning tracker. Never silently skip or declare an
  inactive bundle adopted; blocked explicit adoption needs owner deferral.
  INSPR Calendar Versioning's saved config and shared Pretty/SemVer renderer
  in `inspr-at/inspr` are the default for new presentation adoptions. Vendor
  the exact source and verified complete bundle offline at release preparation;
  runtime never fetches mutable settings. Preserve historical versions.
- [Display weights data](references/calendar-version-display.json): legacy
  display-v1 compatibility data, not the new editor's saved defaults. Existing
  consumers preserve their pin until the reviewed presentation upgrade. Its
  year floor does not restrict presentation-v2, where all weights are adjustable.

These references are normative. A worker marker identifies ownership; it does
not grant approval, acceptance, merge, release, deployment, or secret access.
