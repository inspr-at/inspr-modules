# /secrets — SECRETS domain context

Load the SECRETS domain pack into your context for agenix encryption, env-file pipeline, 1P CLI, secrets rotation, and secret-leak incident response.

@./doctrine/docs/AGENTS-DOMAIN-SECRETS.md

You are now operating with full SECRETS-domain context. The pack covers:

- Agenix pipeline (declare → encrypt → commit → rebuild → /run/agenix/)
- agenix --rekey workflows + multi-island patterns
- Env-file pattern (`~/.inspr/secrets/agents/<NAME>.env` per INSPR-164)
- 1P CLI conventions + per-host entry policy
- Secret-leak incident response (rotate before continuing)
- Secrets-output safety techniques + safe verification primitives

The kernel already enforces the irreversibles (NEVER cat / Read / display secrets, NEVER run env-resolving commands). This pack adds workflow depth and how-to.

Cross-references on demand:

- `/incident` — broader incident-response protocol
- `/nix` — agenix in NixOS context (recipient setup, host keys)
- `/ops` — SSH key rotation, host enrollment

If exhaustive citation needed, see `inspr-modules/docs/AGENTS-CORE.md` topics: `secrets/*`, `security/encrypted-files`, `security/secrets-output`, `incident-response/secret-leak`.
