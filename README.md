# inspr-modules

Reusable Home Manager modules + utilities from the [INSPR](https://inspr.at) initiative.

> *"Where your inspirations live."* — democratize software development by giving anyone the same primitives Markus uses on his own fleet.

## What's here

### Home Manager modules

| Module | Namespace | What it does |
|---|---|---|
| `agent-secrets` | `inspr.secrets.agents` | Materialize agenix-encrypted env files into a per-user "agent-exception" directory at HM activation. Pairs with the env-file pattern (`KEY=value`) for `set -a; source $FILE` consumers. |
| `devenv-direnv-fix` | `inspr.devenv.direnv-fix` | Declaratively materialize devenv's direnv-lib snippet (`~/.config/direnv/lib/z-devenv.sh`) with its colliding `_nix_direnv_preflight` function renamed to `_devenv_preflight`, so it stops shadowing nix-direnv's preflight when both libs are loaded. Source comes from `devenv direnvrc` at build time + `sed`-rename + sanity-grep — auto-tracks devenv version bumps. Without this, `use nix` in any `.envrc` errors with `--no-warn-dirty: command not found`. INSPR-175. |
| `git-atelier-credentials` | `inspr.git.atelier` | Per-atelier outbound git credentials, **forge-agnostic** (works on GitHub, Forgejo, Codeberg, GitLab, Gitea, sourcehut, bare-SSH). **Strategy A** (per-repo SSH deploy keys, narrow servers) and **Strategy B** (per-host user SSH key, account-federated for workstations — the canonical answer to "this machine doesn't have permission to that service") both implemented; **Strategy C** (bot user / access token via credential helper) option-typed and throws on use — INSPR-168 follow-up. Strategy A produces per-repo SSH aliases (`<host>-<atelier>-<repo>`) with narrow URL rewrites; Strategy B produces one alias per atelier (`git-<atelier>`) with owner-prefix URL rewrites covering all repos under `forge.owner` automatically. Per-atelier commit author identity (`git.userName`, `git.userEmail`, optional `git.workspacePath`) wires `includeIf` rules so commits attribute correctly per-persona (gitdir-scoped when `workspacePath` set, else `hasconfig:remote.*.url:` match on git 2.36+). All SSH match blocks use `HostKeyAlias` so one known_hosts entry covers all aliased paths; managed `~/.ssh/known_hosts.d/inspr-git-atelier-<name>` files ship vendor-published host keys for github.com + codeberg.org (self-hosted forges supply via `forge.extraKnownHosts`). Multi-atelier per host supported; Strategy A + B coexist on the same atelier with "longest insteadOf wins" precedence. Full design + 4-tier scaling story in [`inspr/proposals/git-atelier-credentials.md`](https://github.com/markus-barta/inspr/blob/main/proposals/git-atelier-credentials.md). |
| `git-identity` | `inspr.git-identity` | Multi-identity git config with both `gitdir:` AND `hasconfig:remote.*.url:` includeIf rules. The repo's own remote URL picks the identity automatically — no per-host directory list to maintain. |
| `paimos-config` | `inspr.paimos-cli` | Declaratively materializes routing only (`default_instance` + URLs). URLs may be literals or come from a routing env file. It never handles API credentials: INSPR workstations authenticate interactively into the OS keyring; headless automation injects `PAIMOS_URL` + `PAIMOS_API_KEY` into the running process from approved encrypted storage. |
| `ssh-authorized` | `inspr.ssh.authorized` | Declarative `~/.ssh/authorized_keys` via aliased key map + trust list. Manages a marker-delimited block; lines outside the markers (Headscale deploy keys, GitHub Actions OIDC, recovery keys) are preserved across activations. Sorted output → byte-identical regardless of input order. Throws at eval time if `trust` references an undeclared alias. **Rich keys form** (since INSPR-77) supports per-key `{ status; note; }` metadata for grandfathering: `legacy` keys render with a `[legacy]` tag for fleet-wide audit, `revoked` keys keep the declaration as historical record but are not admitted (and throw if accidentally left in `trust`). |
| `default` | (aggregate) | Imports all six above. Consumers wanting à-la-carte should import individual modules. |

### NixOS modules

| Module | Namespace | What it does |
|---|---|---|
| `ssh-authorized` | `inspr.ssh.authorized` | System-side counterpart to the HM `ssh-authorized` (since INSPR-73). Same shared keyring (rich-key form, `status: active \| legacy \| revoked`) but renders into `users.users.<u>.openssh.authorizedKeys.keys` (which NixOS materializes as `/etc/ssh/authorized_keys.d/<u>`). **Multi-user**: `inspr.ssh.authorized.users.<name>.{trust, force, extraKeys}`. **`force = true`** wraps the rendered list in `lib.mkForce` to displace upstream-injected keys (e.g. server-home / hokage profiles); default `false` merges via list concatenation. Throws at eval time on undeclared alias OR revoked-in-trust. Define the `keys` keyring in a plain-Nix file imported at BOTH NixOS-module scope (for this module) AND HM scope (for the HM module) — single source of truth across both. |
| `default` | (aggregate) | Imports all NixOS modules. |

### Packages

| Package | What it does |
|---|---|
| `secrets-audit` | Bash script: detects drift between `secrets/*.age` files and their declarations in `secrets/secrets.nix`. Three modes: human report, `--quiet`, `--json`. |

## Consumer pattern

In your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    inspr-modules.url = "github:markus-barta/inspr-modules";
    inspr-modules.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, inspr-modules, ... }: {
    homeConfigurations.your-host = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      modules = [
        inspr-modules.homeManagerModules.git-identity
        inspr-modules.homeManagerModules.paimos-config
        ./your-home.nix
      ];
    };
  };
}
```

In your `home.nix`:

> **Paimos authentication boundary:** `inspr.paimos-cli` owns routing only. It
> does not read or render API keys. Authenticate a workstation
> interactively after activation; Paimos stores the credential in the OS
> keyring. For headless automation, inject `PAIMOS_URL` + `PAIMOS_API_KEY` into
> the process from approved encrypted storage at runtime only—never put the
> plaintext credential in Nix configuration, the Nix store, or
> `~/.paimos/config.yaml`.

```nix
{
  inspr.git-identity = {
    enable = true;
    default = "personal";
    identities = {
      personal = { name = "Jane Doe"; email = "jane@example.com"; };
      work     = { name = "Jane Doe"; email = "jane@work.com"; };
    };
    contexts.work = {
      identity = "work";
      remoteUrlPatterns = [
        "https://github.com/your-employer/**"
        "**:your-employer/**"
      ];
    };
  };

  inspr.paimos-cli = {
    enable = true;
    defaultInstance = "mine";
    instances.mine = {
      url = "https://your-paimos.example.com";
    };
  };
}
```

For a fresh config, authenticate the workstation at the hidden prompt after
Home Manager activation. If activation reports a legacy `api_key`, do **not**
run this login yet; follow the migration order below first.

```bash
paimos auth login --url https://your-paimos.example.com --name mine
```

The deprecated `apiKeyEnvFile` and `apiKeyVar` options remain accepted for one
compatibility release, emit a warning, and are ignored. This compatibility is
evaluation-only; it does not migrate or reuse a credential. On an existing
legacy consumer, **migrate before any new login**. First force Paimos 4.8 to
load the old config with every auth override unset:

```bash
env -u PAIMOS_URL -u PAIMOS_API_KEY -u PPM_URL -u PPMAPIKEY \
  paimos auth whoami
```

Then retry Home Manager; activation remains fail-closed until the legacy
`api_key` field is gone. Only after that migration may you use interactive
`paimos auth login` if authentication still fails. This order matters because
logging in first can let the subsequent legacy migration overwrite the newly
entered keyring credential. Remove the deprecated Nix options after migration.

For a URL managed outside Nix, set `urlEnvFile` plus `urlVar` instead of `url`.
The file must contain only trusted routing input; credential env files are not
supported by this module.

## Architecture notes — the atelier pattern

These modules emerged from the INSPR onboarding sessions documented in the (private) `inspr` umbrella repo. The design pattern is **the atelier** (formerly called "Pattern β" in older docs — same architecture, more memorable name).

**Atelier metaphor:** imagine a master's workshop where the *tools* (mechanics) are publicly shared, but each *artist's commissions* (per-context values) stay private to that artist. INSPR is structured the same way:

- **The atelier — universal mechanics** (this library: how to materialize secrets, how to compose git includeIfs, how to declare Paimos instance routing). Public, OSS, MIT-licensed. Reusable across every context.
- **Each studio — per-context values** (your flake: identities, instance URLs, fleet patterns). Private to that context. Never shared between studios.

A "studio" (context flake) is anything that consumes inspr-modules + provides its own values: Markus's personal `nixcfg`, his BYTEPOETS work flake, his family flake, future paid-product flakes — each declares its own identity, hosts, and secrets, and gets the rest for free from the shared atelier.

## Testing

Test suite lives under `tests/` and is exposed via `flake.checks.<system>.*`:

```bash
nix flake check --all-systems         # run every test on every supported system
nix build .#checks.aarch64-darwin.secrets-audit-functional --print-build-logs
```

### Tests today

| Check | Coverage |
|---|---|
| `secrets-audit-functional` | Drift detection logic (clean / declared-missing / orphan / commented-out fixtures); `--help` regression test for [INSPR-50](https://github.com/markus-barta/inspr-modules/commit/8fa4b37) (PATH-leak-in-help symptom that prompted the writeShellApplication migration) |
| `paimos-config-functional` | Executes synthetic activations to prove legacy `api_key`, missing files, and unset/empty URL variables preserve the prior config; diagnostics resist shell interpolation; jq encoding safely preserves quoted and multiline routing URLs. Never reads a real user config or credential. |
| `module-eval` (since INSPR-72) | 73 sub-tests across the Home Manager and NixOS modules, run via `lib.evalModules` + stub HM and NixOS harnesses (`tests/module-eval/harness.nix`). Verifies: assertions and throws fire when they should, required options stay required, deprecations warn, Paimos literal/env URL output stays nested under `instances` without credential references, rollout/failure guards precede replacement, git include counts match declarations, and SSH authorization output and guards remain deterministic. Runs entirely at flake-eval time—no activation, real HM, or network. |

### Local dev (without nix sandbox)

```bash
nix build .#secrets-audit
./tests/secrets-audit/run-tests.sh
```

### Roadmap

- ~~Module-eval tests for HM modules~~ — **shipped (INSPR-72)**, see above.
- NixOS VM integration tests via `pkgs.testers.runNixOSTest` — heavy but the gold standard for "does activation actually work end-to-end." Filed as a follow-up.

## Versioning + deprecation policy

Semantic versioning: **MAJOR.MINOR.PATCH** per [semver.org](https://semver.org/).

- **PATCH** — bugfixes, doc improvements, no API surface changes
- **MINOR** — new options, new modules, deprecations (still backward-compatible)
- **MAJOR** — breaking changes (removals, semantic changes, renames without aliases)

Option renames go through a **deprecation window**:

1. New option lands in a MINOR release; old option is marked deprecated (`visible = false` in option docs; emits a `warnings = [ ... ]` at eval time) and continues to work as an alias.
2. Old option is **removed** in the next MAJOR release; consumers have at least one MINOR cycle to migrate.
3. Each deprecation + removal is recorded in [CHANGELOG.md](./CHANGELOG.md).

**Example** (current — `inspr.secrets.agents.identityFile` → `identityFiles`):
```nix
# Old (still works, emits eval warning, removed in v0.2.0):
inspr.secrets.agents.identityFile = "$HOME/.ssh/id_rsa";

# New (preferred):
inspr.secrets.agents.identityFiles = [
  "$HOME/.ssh/id_ed25519"
  "$HOME/.ssh/id_rsa"
];
```

## Recovery scenarios

What to do when things go wrong:

| Scenario | What you'll see | Recovery |
|---|---|---|
| **User SSH key changes** (e.g., regenerated id_ed25519) | `agent-secrets` activation fails: `age: cannot decrypt …` | Re-rekey the .age files: add the new pubkey to your nixcfg's `secrets/secrets.nix` recipients, then `cd secrets && agenix --rekey`. The OLD key continues to decrypt until you remove it. |
| **Activation half-completes** (e.g., one `.age` file is corrupt) | Partial decrypt; `set -e` exit; doctor flags missing secrets | The relock-trap (since v0.1.0) ensures the dir is still 0500 outside activation. Fix the corrupt `.age` file (or remove its declaration) and re-run `home-manager switch`. |
| **Headscale / control server is down** | `inspr-doctor` flags `headscale_reachable` ✗ | Tailnet keeps working with last-known peers; no immediate action. Wait for control plane to recover. |
| **Manual edit to `~/Secrets/age/decrypted/agents/`** | Directory is 0500 → write fails OR (if you chmod'd) overwritten on next switch | Don't manually edit. The dir is activation-managed. Re-encrypt the source `.age` file via `agenix -e`. |
| **`paimos auth whoami` fails** | The OS-keyring credential (interactive) or `PAIMOS_API_KEY` runtime input (headless) may be missing/rotated | First confirm `paimos_instance_config` passes. Then re-authenticate interactively with `paimos auth login --url INSTANCE_URL --name INSTANCE_NAME` and enter the credential at the hidden prompt, or repair the headless runtime injection without printing the value. |
| **Paimos activation refuses an existing legacy `api_key` config** | Home Manager stops before creating or replacing `config.yaml`; the old config remains unchanged | Before any new login, run `env -u PAIMOS_URL -u PAIMOS_API_KEY -u PPM_URL -u PPMAPIKEY paimos auth whoami` once to trigger the Paimos 4.8 migration, then retry Home Manager. Use interactive `paimos auth login` only after activation no longer reports the legacy field and only if auth still fails. |
| **`pm.barta.cm` / your Paimos instance is down** | `paimos auth whoami` fails; doctor flags `paimos_auth` ✗ | Transient — wait. Local instance routing remains available. |
| **Eval-time error: "hostname could not be determined"** (since v0.1.0) | nix-rebuild fails immediately | Pass `hostname` via `extraSpecialArgs` in your homeConfigurations entry, OR set `inspr.secrets.agents.hostname = "your-host"` explicitly. |
| **Eval-time error: "defaultInstance must be a key in instances"** (since v0.1.0) | nix-rebuild fails immediately | Typo in `inspr.paimos-cli.defaultInstance`, or you set it but never declared the corresponding instance. Fix and re-eval. |
| **First fresh host: `agent-secrets` discovery returns zero** | Activation succeeds but dir is empty | Either you forgot to set `inspr.secrets.agents.encryptedRoot`, OR your repo's secrets/agents subdir is empty / not git-tracked. (Untracked files are invisible to flake eval.) |

## License

MIT — deliberately permissive. This is a *library*; restrictive licenses on infrastructure modules would discourage exactly the adoption the mission depends on.

## Status

v0.1.0 — extracted from `markus-barta/nixcfg` on 2026-05-02. Tested on:
- macOS workstation (M5, aarch64-darwin)
- macOS workstation (imac0, x86_64-darwin)
- NixOS server (csb0, x86_64-linux)

via `inspr-doctor` (private repo today; the script itself is published in
the inspr-modules CHANGELOG once it's been generalized for non-Markus
consumers — see roadmap).

Roadmap:
- NixOS-equivalent modules (currently HM-only — server-side `system_agenix_decrypted` is a doctor check, not yet a module here)
- 1Password tag-export integration (Phase 2 secrets graduation)
- Remove the ignored `paimos-config` `apiKeyEnvFile` / `apiKeyVar` compatibility options after their one-release deprecation window (INSPR-225)
