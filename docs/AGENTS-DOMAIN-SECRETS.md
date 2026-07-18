# AGENTS — Domain: Secrets

*Layer: `domain:secrets` · INSPR-189 Phase 6 · Loaded on demand by `/secrets`.*

Detailed rules for secrets, agenix, env-files, 1Password. Kernel (auto-loaded) has the hard irreversibles ("never cat a secret file", "STOP on leak"). This pack adds technique, depth, incident-response playbook.

**Load before**: touching `~/.inspr/secrets/`, `*.age`, `*.env`, agenix CLI, AGE recipient rotation, 1P entries, or pipeline verification. Just sourcing-then-calling `paimos` is kernel-only.

---

## Pattern: env-file pipeline (INSPR-164, canonical fleet-wide)

Agent secrets are auto-materialized at:

```
/Users/<u>/.inspr/secrets/agents/<NAME>.env
```

The filename equals the env-var name (e.g. `PPMAPIKEY.env` → `$PPMAPIKEY`). Daily interface — and the **only** correct way to consume them:

```bash
( set -a; source ~/.inspr/secrets/agents/<NAME>.env; cmd; set +a )
```

Subshell scoping prevents leakage to the caller's environment. The `set -a` / `set +a` bracket is bash-only — wrap in `bash -c '…'` from fish.

### Tool-specific exceptions to env-file consumption

Not every tool reads env-files. Some use OS keyrings, others use config files. Two notable exceptions:

- **`paimos` CLI** uses the OS keyring (entry `paimos-cli/<instance>`).
  INSPR workstations seed it interactively through the hidden prompt of
  `paimos auth login`; INSPR does not declaratively provision keyring
  credentials. Headless/CI credentials may come from approved encrypted
  storage such as agenix, but must be injected only into the running process
  and never rendered into plaintext YAML, a repository, the Nix store,
  activation output, arguments, or logs. Sourcing `PPMAPIKEY.env` alone does
  not authenticate `paimos`; the legacy alias requires the complete pair
  `PPM_URL` + `PPMAPIKEY`. Prefer `PAIMOS_URL` + `PAIMOS_API_KEY` for headless
  operation. Use `PPMAPIKEY.env` alone only for raw `curl` against
  `pm.barta.cm/api/...`. Full setup in `/ppm` (INSPR-193, INSPR-225, PAI-685).
- **1Password CLI (`op`)** uses its own session token; `op signin` writes session state to `~/.config/op/`. No env-file involved for daily use.

When piping a new env-file to a CLI, check the CLI's docs first — env-var name mismatch is the most common silent failure mode.

### Naming convention

- Materialized env files: name after the consumer tool's documented env-var convention (e.g. `GH_TOKEN.env` so `gh` picks it up automatically).
- Tier-3 secrets decrypted to disk: `chmod 600` immediately.
- Extensions encode content type — never reuse one extension across types (the Day-11 leak happened because `.env` was used for both env vars *and* SSH keys; a glob-source loop sourced the SSH key as if it were KEY=VALUE).

### Glob+source guardrails

Any glob + source/exec/eval loop needs a per-iteration invariant check:
- Content sniff: `head -c 64 | grep -E '^[A-Z_]+='` to admit only `KEY=value` files
- File-size sanity (encrypted blob ≥ 5 KB)
- Or each file's type visible from name alone, no inspection needed

## Pattern: agenix encryption pipeline

**Order is ALWAYS**: `declare → encrypt → commit`. Skip declare and `agenix -e` errors with "attribute missing".

```bash
# 1. declare in secrets/secrets.nix (manual edit)
# 2. encrypt
cd ~/Code/nixcfg/secrets        # cd to load only bare-rules secrets.nix; avoids 18× rekey iteration noise
agenix -e <name>.age             # uses $EDITOR
# 3. commit the .age blob to git
```

### Non-interactive encryption

`EDITOR='cp $src'` silently encrypts 0 bytes when stdin is non-TTY. Pipe content via stdin instead:

```bash
agenix -e dest.age < src
```

### Recipient changes

- Adding/removing recipients on existing `.age` files **always** requires `agenix --rekey`. Without it, the change is metadata-only and the blob keeps the old recipients.
- For a repo spanning multiple isolation islands, pass MULTIPLE `-i` flags on a single rekey — rekey is all-or-nothing and aborts on first error:
  ```bash
  agenix --rekey -i ~/.ssh/island_a_ed25519 -i ~/.ssh/island_b_ed25519
  ```
- Verify rekey by **decrypting with the NEW identity** — exit code alone can mean "kept old recipients and added nothing".
- After rekey, verify with `git status` + size comparison before assuming destructive failure. agenix's atomic-write safety prevents in-place corruption.

### AGE recipient rotation sequence

```
add new recipient → agenix --rekey → verify decrypt with new key
                  → remove old recipient → agenix --rekey again
```

Never remove a recipient before rekeying first — highest-risk delete in the inventory. Every `agents/*` `.age` file MUST include the user as an AGE recipient (HM-standalone activation cannot read root-owned host keys).

### macOS host onboarding

On every macOS host that becomes an agenix recipient, manually generate a dedicated `/etc/ssh/ssh_host_ed25519_key` with `ssh-keygen` as the agenix identity anchor.

### Reserved for user

- `just rekey` is **user-only** — never run from an agent.
- All `.age` and `.env` modifications: ASK first, GUIDE the user to run the command, VERIFY size before/after.

## Pattern: 1Password as canonical store

- Default to per-host 1P entries for any infra credential — never reuse names that imply broader coverage than they actually have.
- Don't propose sops, pass, env-vars-in-shell, or any parallel store unless explicitly asked to compare.
- The SSH-host-key-as-AGE-recipient bootstrap is solved — don't keep flagging it as novel.

## Verification primitives (safe only)

- Var is set: `[ -n "$VAR" ] && echo set`
- File exists: `ls -la <file>`
- Count files: `ls <dir> | wc -l`
- Content sniff: `file <path>`
- Error count: grep with explicit pattern

Never `echo $VAR`, `printf`, or any transform-then-display.

## Workflow: filtered command returns empty

If a filtered command returns empty unexpectedly, **DO NOT** remove the filter and re-run unfiltered. Diagnose the underlying state — the filter was probably correct. The unfiltered re-run is what leaks. (Day-11 incident.)

## Workflow: secret-leak incident response

If a secret value appears in any tool output:

1. **STOP** the current command chain. Don't run further commands touching the same pipeline.
2. **Do not reference, repeat, or quote** the value. Name the affected variable (e.g. "PPMAPIKEY"), never the value.
3. **Alert the user immediately.** One sentence: which var, which command leaked it, no value.
4. **Treat as compromised.** Rotate the credential before continuing.
5. If transcripts left the local machine (cloud-uploaded, shared, copy-pasted), assume leaked-by-default — prefer immediate rotation over containment analysis.
6. Secret hit git commit: STOP before push if not pushed; if pushed, rotate. Discuss next steps with user.
7. Encrypted file corrupted (bad rekey, partial write): STOP, alert, guide restore from git, then rotate.

### Pre-flight checklist (mental, every Bash call in secret-adjacent context)

Before each command, ask:
- Could stdout/stderr contain a secret value?
- Does it touch `~/.inspr/secrets/`, `~/Secrets/`, `~/.ssh/<not-pub>`, `/run/agenix/`, `/run/secrets/`, `*.env`, `*.age`, `*.gpg`?
- Does it involve `env`, `printenv`, `set`, `declare`, `export`, `direnv export`, `source`, `cat`, `head`, `tail`?
- Did a previously filtered command return unexpectedly empty?

If yes to any: redesign the command before running. The principle (any command whose output IS the resolved environment is forbidden) is what matters — the literal forbidden-list will never be exhaustive.

## Workflow: bootstrap scripts that write .env

- Default stdout to `<redacted, length=N>`; cleartext via opt-in (`--print-secret`) only.
- Multi-secret bootstraps use **per-key boolean pairs** (`WRITE_X` + `ROTATE_X`), NOT a single `--write-env` flag that rotates everything.
- Maintain ONE executable bootstrap as canonical state spec; bake all known init traps into it.

## Constraint: never see-the-value workflow

If a workflow seems to require seeing the value (vs using it via env-loaded process), **stop and ask**. No "just this once is fine". Don't copy to "stage" elsewhere. Don't decrypt-and-display, base64-decode-and-display, or transform-then-display.

When Markus needs the value himself (paste into a web form, copy to a phone): use 1Password via `op` CLI in his interactive shell — don't echo through your stdout. Provide the command, let him run it.

---

*See also*: `/incident` (broader leak response), `/dev` (commit secret-scan), `/nix` (agenix module wiring). Full source: `AGENTS-CORE.md` topics `secrets/*`, `security/secrets-output`, `incident-response/secret-leak`, `tools/agenix`, `tools/bootstrap-scripts`.*
