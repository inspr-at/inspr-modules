# /nix — NIX domain context

Load the NIX domain pack into your context for nix-darwin, Home Manager, devenv, NixOS module design, build safety, activation gotchas.

@./doctrine/docs/AGENTS-DOMAIN-NIX.md

You are now operating with full NIX-domain context. The pack covers:

- Flake hygiene (`git add -N` before flake operations, etc.)
- Module design (multi-user shapes, `lib.evalModules` debugging, build-time asserts)
- HM activation patterns (DAG ordering, umask hygiene, PATH minimalism)
- NixOS build safety (`mutableUsers`, `nix-ld`, kernel-staging, hashedPasswordFile)
- nix-darwin specifics (per-host divergence, brew→nix migration)
- Common pitfalls (Nix multiline strings, `or` keyword limitations)

Reminder of kernel rule: **NEVER build NixOS configs on macOS.** From macOS, build remotely via ssh. macOS Home Manager configs CAN build locally.

Cross-references on demand:

- `/secrets` — agenix recipient setup, host keys, .age file management
- `/ops` — SSH to NixOS hosts, deploy workflow

If exhaustive citation needed, see `inspr-modules/docs/AGENTS-CORE.md` topics: `nix/*`, `nixos/*`.
