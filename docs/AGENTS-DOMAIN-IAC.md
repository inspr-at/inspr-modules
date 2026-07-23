# AGENTS — Domain: IAC (Infrastructure as Code, Layer 5)

*Layer: `domain:iac` · INSPR-199 (2026-05-23) · Loaded on demand by `/iac`.*

Detailed rules for **Layer 5 — Service Configuration**: declarative state for things that have their own management APIs (Zitadel, Cloudflare, GitHub, Headscale, etc.). Kernel covers irreversibles (no destructive git, encrypted-file rules). This pack adds the "Nix vs Terraform vs agenix" rubric, the inspr-services repo pattern, provider conventions, and drift response.

**Load before**: editing service config that has its own API (Zitadel orgs/apps, Cloudflare DNS records, GitHub repo settings, Headscale ACLs, vault config). Pair with `/nix` if the work also touches host config, `/secrets` if it touches credentials.

---

## The INSPR stack — which layer owns what

```
L7 — Doctrine + agent operating layer        (inspr-modules, inspr CLI)
L6 — Applications & data                     (Paimos, Pharos, Janus, customer apps)
L5 — Service configuration (Terraform/IaC)   ← THIS PACK
L4 — Secrets at rest                         (agenix .age, ~/.inspr/secrets/agents/, 1Password)
L3 — OS / host config                        (nix-darwin, NixOS — nixcfg)
L2 — Network / mesh                          (Tailscale + Headscale, Cloudflare DNS surface)
L1 — Hardware                                (iMacs, MBPs, NixOS servers — Pharos inventory)
```

**L5 owns**: API-managed service state that does NOT need OS rebuild and does NOT live inside an application. Examples: Zitadel project/app/grant definitions, Cloudflare DNS records, GitHub repo branch protection, Headscale ACL policy, Vaultwarden org config.

## Pattern: Nix vs Terraform vs agenix — which tool

- 🔴 **Nix (L3, nixcfg)** owns OS-level state: packages, systemd services, file paths, user accounts, kernel modules. Anything that needs a `nixos-rebuild switch` or `home-manager switch` to take effect.
- 🔴 **Terraform (L5, inspr-services)** owns API-managed service state: configurations applied via the service's own REST/GraphQL/CLI surface. Anything that's reconciled by `terraform apply`, not by an OS rebuild.
- 🔴 **agenix (L4, nixcfg/secrets/)** owns secrets at rest: encrypted material decrypted into `/run/agenix/` (NixOS) or `~/.inspr/secrets/agents/<NAME>.env` (host runtime). Used by **both** L3 and L5 — never duplicate secrets between tools.
- 🟡 If you find yourself templating service config into a Nix expression: STOP. That's a sign it belongs in L5, not L3.
- 🟡 If a Terraform provider for the target exists and is maintained, prefer it over a custom reconciler script.
- 🟢 When in doubt: needs OS rebuild? → Nix. Reconciles via API call? → Terraform. Encrypted file? → agenix.

## Pattern: inspr-services repo layout

- 🟡 Home for L5 code: **`~/Code/inspr-services/`** (sibling to nixcfg, fleetcom, inspr).
- 🟡 Per-service subdirectory: `services/<service>/` (e.g., `services/zitadel/`, `services/cloudflare/`).
- 🟡 Each service dir contains: `*.tf` files, `RUNBOOK.md`, optional `tests/` (post-apply health probes), `.terraform.lock.hcl`.
- 🟡 Repo-root `justfile` provides cross-cutting recipes (`just plan <service>`, `just apply <service>`, `just status`).
- 🟢 State file storage: encrypted via agenix as `<service>/state.tfstate.age`, OR remote state in Tailscale-protected object storage. **Never commit unencrypted state.**

## Pattern: just-recipe ergonomics (mirror nixcfg)

| nixcfg | inspr-services |
|---|---|
| `just switch` | `just apply <service>` |
| `just check` / `nix flake check` | `just plan <service>` |
| `just edit-secret` | (reuse agenix from nixcfg/secrets/) |
| `hosts/<name>/docs/RUNBOOK.md` | `services/<name>/RUNBOOK.md` |

- 🟡 Recipe naming mirrors nixcfg so muscle memory transfers. Don't invent new verbs.
- 🟡 `just plan` MUST be safe to run from any host at any time. `just apply` MAY require an interactive confirmation (default behavior of `terraform apply`).
- 🟢 `just status <service>` should run the post-apply health probe(s) for that service — drift detection in one command.

## Pattern: provider catalog

Approved providers (add to this list as L5 adopts new surfaces):

| Provider | Target | Notes |
|---|---|---|
| `zitadel/zitadel` | auth.inspr.at | INSPR-198 first user |
| `cloudflare/cloudflare` | barta.cm DNS zone | replaces `nixcfg/infrastructure/cloudflare/dns-barta-cm.md` markdown manifest |
| `integrations/github` | github.com/markus-barta/* repos | branch protection, webhooks, repo settings |
| `headscale-headscale` (or fork) | hs.barta.cm | ACL policy migration (currently nixcfg-resident) |

- 🟡 **Pin provider versions** in `terraform { required_providers { ... } }`. Floating versions break reproducibility.
- 🟡 Each new provider requires a doctrine note here AND a `services/<name>/RUNBOOK.md`.
- 🟢 Prefer official providers over community forks when both exist; pick a fork only with explicit reasoning in RUNBOOK.

## Pattern: secrets in Terraform

- 🔴 **Provider tokens come from agenix-decrypted env files** at `~/.inspr/secrets/agents/<PROVIDER>_TOKEN.env`. Source via `( set -a; source FILE; cmd; set +a )` — same pattern as kernel.
- 🔴 **NEVER commit a `.tfvars` with real credentials.** `.tfvars.example` with placeholders is fine.
- 🔴 **NEVER `terraform output` a value marked `sensitive = true` to a shared terminal.** Same secret-output rules as kernel — apply the principle.
- 🟡 Mark all credentials in TF as `sensitive = true` so `terraform plan` doesn't echo them.
- 🟡 State files contain plaintext secrets in transit — encrypt with agenix at rest (`state.tfstate.age`).

## Pattern: drift detection + response

- 🟡 `terraform plan` exiting non-zero (drift detected) is a normal, recoverable state — investigate before applying.
- 🟡 If drift is detected and you didn't cause it: STOP. Likely another agent / human made a manual change. `git log` + ask before reconciling.
- 🟡 Run `just plan <service>` on a schedule (cron / CI nightly) to catch external drift early.
- 🟢 When fixing drift: prefer "import the change into Terraform" over "revert the change" if the manual edit was intentional.

## Pattern: CI gates (per L5 epic INSPR-199)

- 🟡 CI runs `terraform fmt -check` + `terraform validate` + `terraform plan` on every PR.
- 🟡 CI runs `terraform apply` on merge to main, gated by manual approval for production-impacting services (Zitadel, DNS, GitHub).
- 🟡 Failing plan blocks the PR — drift cannot land silently.
- 🟢 Per-service post-apply health probe runs as part of `just apply` AND in CI.

## Pattern: service health probing (parallel to `inspr check`)

L3 hosts are checked via `inspr check`. L5 services need an analog:

- 🟡 Each service in `services/<name>/tests/` defines health probes (e.g., for Zitadel: admin can list orgs; Console returns 200; OIDC token endpoint responds).
- 🟡 `inspr fleet-check` (future) aggregates these across all L5 services.
- 🟢 Health probes go in the heal-flow registry so `inspr heal` can suggest fixes for known L5 drift symptoms.

## Pattern: declarative-everywhere posture

The INSPR operating layer is declarative across all surfaces:

- L3 (OS) — Nix
- L4 (secrets) — agenix
- L5 (services) — Terraform
- L2 (DNS in particular) — converging into L5 over time

If you're tempted to add an imperative bootstrap script: that's a code smell. Push it into the appropriate declarative layer. (INSPR-185 / INSPR-198 — `bootstrap-zitadel.sh` is the textbook anti-pattern this layer eliminates.)

## Pattern: documenting service-specific quirks

- 🟡 Every service directory has a `RUNBOOK.md` that covers: provider gotchas, manual import procedure (first-time bootstrap), state recovery, health-probe interpretation.
- 🟡 Cross-reference to upstream provider docs by version (provider docs drift; pin them).
- 🟢 When a service's quirks become enough to warrant their own doctrine pack: promote (e.g., a future `AGENTS-DOMAIN-ZITADEL.md`).

---

*See also*: `/nix` (L3 ergonomics this pack mirrors), `/secrets` (L4 agenix integration), `/ops` (L2 fleet + cross-host). Tracking epic: **INSPR-199** (Service configuration layer). First child: **INSPR-198** (declarative Zitadel).*
