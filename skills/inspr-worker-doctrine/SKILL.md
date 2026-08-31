---
name: inspr-worker-doctrine
description: "Mandatory INSPR worker-start and versioning doctrine. Read before material work, worker delegation, or changing any version-bearing artifact."
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
  `YY.MM.DD[.hh.mm.ss]` is the gradual INSPR default, but every repository
  remains on its current scheme until its own approved migration is complete.

These references are normative. A worker marker identifies ownership; it does
not grant approval, acceptance, merge, release, deployment, or secret access.
