# /iac — IAC (L5 service-config) domain context

Load the IAC domain pack into your context for Terraform-managed declarative service configuration: Zitadel, Cloudflare DNS, GitHub repo settings, Headscale ACLs, future L5 surfaces.

@./doctrine/docs/AGENTS-DOMAIN-IAC.md

You are now operating with full IAC-domain context. The pack covers:

- The INSPR stack layer model (L7 doctrine down to L1 hardware)
- The "Nix for OS, Terraform for services, agenix for secrets" rubric
- `inspr-services/` repo layout + just-recipe ergonomics (mirrors nixcfg)
- Approved Terraform provider catalog
- Secrets pattern in Terraform (agenix-decrypted env files, never commit `.tfvars` with real creds)
- Drift detection + response workflow
- CI gates (plan on PR, apply on merge with manual approval)
- Service health probing (parallel to `inspr check` for L3 hosts)
- Declarative-everywhere posture (no more bootstrap-X.sh scripts)

The kernel already enforces secret-output safety + destructive-git rules. This pack adds the L5-specific workflow + layer-boundary discipline.

Cross-references on demand:

- `/nix` — L3 ergonomics this pack mirrors (just switch vs just apply)
- `/secrets` — L4 agenix integration (provider tokens + state encryption)
- `/ops` — L2 fleet context (Tailscale-protected state, multi-host coordination)
- `/ppm` — tracking epic INSPR-199 + child tickets

If a service is large enough to deserve its own doctrine: promote to `AGENTS-DOMAIN-<SERVICE>.md` and add a router row. Default home stays here.
