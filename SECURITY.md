# Security policy

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting on this repository:
**Security → Report a vulnerability**. That opens a private thread visible only
to the maintainer.

If that is unavailable to you, open a public issue containing **no detail** —
just a request for a private channel — and you will be contacted.

## What to expect

| | |
|---|---|
| Acknowledgement | within 7 days |
| Assessment | within 30 days |
| Fix or documented mitigation | tracked publicly once a fix exists |

This is a small project maintained by one person. Those are honest targets, not
a commercial SLA.

## Scope

In scope: the Nix and Home Manager modules, the `inspr` CLI, and the guard
scripts in `scripts/`.

Particularly wanted:

- a way to make `leak-guard.sh` pass while operator-identifying content reaches
  the public surface
- a way to make `doctrine-check.sh` report a repository clean while its doctrine
  wiring does not actually resolve
- anything that causes a secret to be written to disk unencrypted, logged, or
  printed by these modules

Both guards are known to be incomplete — see INSPR-300. Reports that a guard
misses something are useful and welcome; that is the point of this section.

Out of scope: the operator's own fleet, hosts and infrastructure. This
repository is identity-free by design and describes no live system.

## Supported versions

Only the latest tag receives fixes. See the support matrix in the README.
