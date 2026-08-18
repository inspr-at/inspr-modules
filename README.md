# inspr-modules

Reusable Home Manager modules + utilities from the [INSPR](https://inspr.at) initiative.

> *"Where your inspirations live."* — democratize software development by giving anyone the same primitives Markus uses on his own fleet.

## What's here

### Home Manager modules

| Module | Namespace | What it does |
|---|---|---|
| `agent-secrets` | `inspr.secrets.agents` | Materialize agenix-encrypted env files into a per-user "agent-exception" directory at HM activation. Pairs with the env-file pattern (`KEY=value`) for `set -a; source $FILE` consumers. |
| `agent-skills` | `inspr.agent-skills` | Declarative agent-skill provisioning across CLI harnesses. Materializes skill directories (SKILL.md convention) into every configured harness skills path — Claude Code `~/.claude/skills/` and Codex `~/.codex/skills/` by default, extensible per consumer — as read-only /nix/store symlinks. Skills are either **bundled** (shipped in this repo under `skills/<name>/` — currently `ship-next`, `housekeeping`, `tidyrepo`, `product-gauntlet`) or **external** (any pinned path, e.g. a `fetchFromGitHub` of anthropics/skills). Per-skill harness subsetting via `skills.<name>.harnesses`. One source of truth per skill; per-harness copies cannot drift. |
| `devenv-direnv-fix` | `inspr.devenv.direnv-fix` | Declaratively materialize devenv's direnv-lib snippet (`~/.config/direnv/lib/z-devenv.sh`) with its colliding `_nix_direnv_preflight` function renamed to `_devenv_preflight`, so it stops shadowing nix-direnv's preflight when both libs are loaded. Source comes from `devenv direnvrc` at build time + `sed`-rename + sanity-grep — auto-tracks devenv version bumps. Without this, `use nix` in any `.envrc` errors with `--no-warn-dirty: command not found`. INSPR-175. |
| `git-atelier-credentials` | `inspr.git.atelier` | Per-atelier outbound git credentials, **forge-agnostic** (works on GitHub, Forgejo, Codeberg, GitLab, Gitea, sourcehut, bare-SSH). **Strategy A** (per-repo SSH deploy keys, narrow servers) and **Strategy B** (per-host user SSH key, account-federated for workstations — the canonical answer to "this machine doesn't have permission to that service") both implemented; **Strategy C** (bot user / access token via credential helper) option-typed and throws on use — INSPR-168 follow-up. Strategy A produces per-repo SSH aliases (`<host>-<atelier>-<repo>`) with narrow URL rewrites; Strategy B produces one alias per atelier (`git-<atelier>`) with owner-prefix URL rewrites covering all repos under `forge.owner` automatically. Per-atelier commit author identity (`git.userName`, `git.userEmail`, optional `git.workspacePath`) wires `includeIf` rules so commits attribute correctly per-persona (gitdir-scoped when `workspacePath` set, else `hasconfig:remote.*.url:` match on git 2.36+). All SSH match blocks use `HostKeyAlias` so one known_hosts entry covers all aliased paths; managed `~/.ssh/known_hosts.d/inspr-git-atelier-<name>` files ship vendor-published host keys for github.com + codeberg.org (self-hosted forges supply via `forge.extraKnownHosts`). Multi-atelier per host supported; Strategy A + B coexist on the same atelier with "longest insteadOf wins" precedence. The full design and 4-tier scaling story live in the maintainer's private design notes; the option documentation in `modules/home-manager/git-atelier-credentials.nix` is self-contained. |
| `git-identity` | `inspr.git-identity` | Multi-identity git config with both `gitdir:` AND `hasconfig:remote.*.url:` includeIf rules. The repo's own remote URL picks the identity automatically — no per-host directory list to maintain. |
| `inspr-cli` | `inspr.cli` | Renders the `inspr` CLI's fleet configuration (Headscale, tracker, Pharos, expected git identity). Endpoints and identity metadata only — never credentials. Unset values make the dependent checks SKIP rather than FAIL, so the CLI is useful before you have configured anything. |
| `paimos-config` | `inspr.paimos-cli` | Declaratively materializes routing only (`default_instance` + URLs). URLs may be literals or come from a routing env file. It never handles API credentials: INSPR workstations authenticate interactively into the OS keyring; headless automation injects `PAIMOS_URL` + `PAIMOS_API_KEY` into the running process from approved encrypted storage. |
| `ssh-authorized` | `inspr.ssh.authorized` | Declarative `~/.ssh/authorized_keys` via aliased key map + trust list. Manages a marker-delimited block; lines outside the markers (Headscale deploy keys, GitHub Actions OIDC, recovery keys) are preserved across activations. Sorted output → byte-identical regardless of input order. Throws at eval time if `trust` references an undeclared alias. **Rich keys form** (since INSPR-77) supports per-key `{ status; note; }` metadata for grandfathering: `legacy` keys render with a `[legacy]` tag for fleet-wide audit, `revoked` keys keep the declaration as historical record but are not admitted (and throw if accidentally left in `trust`). |
| `default` | (aggregate) | Imports seven of the eight above — **`inspr-cli` is excluded on purpose**, because it writes a `fleet.conf` and should be an explicit opt-in rather than something an aggregate turns on for you. Import it by name if you want it. Consumers wanting à-la-carte should import individual modules. |

### NixOS modules

| Module | Namespace | What it does |
|---|---|---|
| `ssh-authorized` | `inspr.ssh.authorized` | System-side counterpart to the HM `ssh-authorized` (since INSPR-73). Same shared keyring (rich-key form, `status: active \| legacy \| revoked`) but renders into `users.users.<u>.openssh.authorizedKeys.keys` (which NixOS materializes as `/etc/ssh/authorized_keys.d/<u>`). **Multi-user**: `inspr.ssh.authorized.users.<name>.{trust, force, extraKeys}`. **`force = true`** wraps the rendered list in `lib.mkForce` to displace upstream-injected keys (e.g. server-home / hokage profiles); default `false` merges via list concatenation. Throws at eval time on undeclared alias OR revoked-in-trust. Define the `keys` keyring in a plain-Nix file imported at BOTH NixOS-module scope (for this module) AND HM scope (for the HM module) — single source of truth across both. |
| `default` | (aggregate) | Imports all NixOS modules. |

### Packages

| Package | What it does |
|---|---|
| `inspr` | The INSPR CLI (evolved from `inspr-doctor`, INSPR-195): `check` (read-only drift diagnosis, incl. the kernel byte-budget gate), `heal` (apply mapped fixes with verified-applied semantics), `onboard` (fresh-host walkthrough, optional Pharos registration), `post-deploy` (nixcfg → Pharos → HostDash validation). |
| `secrets-audit` | Bash script: detects drift between `secrets/*.age` files and their declarations in `secrets/secrets.nix`. Three modes: human report, `--quiet`, `--json`. |

## Consumer pattern

In your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # Pin to a tag. Tracking `main` means every `nix flake update`
    # can change doctrine and module behaviour under you.
    inspr-modules.url = "github:inspr-at/inspr-modules/v0.4.2";
    inspr-modules.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, inspr-modules, ... }: {
    homeConfigurations.your-host = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      modules = [
        inspr-modules.homeManagerModules.git-identity
        # add other modules by name; `paimos-config` is shown further down
        ./your-home.nix   # your existing config — must set home.username,
                          # home.homeDirectory and home.stateVersion, as any
                          # Home Manager configuration does
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

### NixOS: `ssh-authorized`

The NixOS module imports at system scope, not through Home Manager. A
module-integration example — **not** a bootable system on its own; add it to a
configuration that already has a filesystem, bootloader and
`system.stateVersion`. Every alias in `trust` must be declared in `keys`, or
eval fails on purpose:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    inspr-modules.url = "github:inspr-at/inspr-modules/v0.4.2";
    inspr-modules.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, inspr-modules, ... }: {
    nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        inspr-modules.nixosModules.ssh-authorized
        ({ ... }: {
          users.users.alice = { isNormalUser = true; };

          inspr.ssh.authorized = {
            enable = true;
            keys = {
              "alice@laptop" = "ssh-ed25519 AAAA...";     # your real public key
              "alice@workstation" = "ssh-ed25519 AAAA...";
            };
            users.alice = {
              trust = [ "alice@laptop" "alice@workstation" ];
              force = true;   # the rendered list is authoritative
            };
          };
        })
      ];
    };
  };
}
```

This is the same shape the VM integration test boots (`tests/nixos-vm/`), and
that test proves the **module** admits trusted keys and refuses untrusted,
revoked and cross-user ones on a running sshd. It does not prove *your* keys:
the option accepts any string, so a typo in a public key evaluates fine and
fails only at login. Check with `ssh-keygen -l -f <(echo "<key>")` before you
commit it; build-time key validation is on the roadmap. Full option reference: the header of
[`modules/nixos/ssh-authorized.nix`](modules/nixos/ssh-authorized.nix).

## Architecture notes — the atelier pattern

These modules emerged from the INSPR onboarding sessions documented in the (private) `inspr` umbrella repo. The design pattern is **the atelier** (formerly called "Pattern β" in older docs — same architecture, more memorable name).

**Atelier metaphor:** imagine a master's workshop where the *tools* (mechanics) are publicly shared, but each *artist's commissions* (per-context values) stay private to that artist. INSPR is structured the same way:

- **The atelier — universal mechanics** (this library: how to materialize secrets, how to compose git includeIfs, how to declare Paimos instance routing). Public, OSS, and licensed under AGPL-3.0-only. Reusable across every context.
- **Each studio — per-context values** (your flake: identities, instance URLs, fleet patterns). Private to that context. Never shared between studios.

A "studio" (context flake) is anything that consumes inspr-modules + provides its own values: Markus's personal `nixcfg`, his family flake, future paid-product flakes — each declares its own identity, hosts, and secrets, and gets the rest for free from the shared atelier.

## Testing

Test suite lives under `tests/` and is exposed via `flake.checks.<system>.*`:

```bash
nix flake check --all-systems         # run every test on every supported system
nix build .#checks.aarch64-darwin.secrets-audit-functional --print-build-logs
```

### Tests today

| Check | Coverage |
|---|---|
| `license-surface` | Canonical AGPLv3 text, exact AGPL-3.0-only declarations across public/source/doctrine surfaces, and Nix package metadata for both shipped utilities |
| `repository-location-surface` | Canonical INSPR organization links, clone guidance, and Pharos container default, while explicitly preserving the intentionally personal `nixcfg` location |
| `secrets-audit-functional` | Drift detection logic (clean / declared-missing / orphan / commented-out fixtures); `--help` regression test for [INSPR-50](https://github.com/inspr-at/inspr-modules/commit/8fa4b37) (PATH-leak-in-help symptom that prompted the writeShellApplication migration) |
| `paimos-config-functional` | Executes synthetic activations to prove legacy `api_key`, missing files, and unset/empty URL variables preserve the prior config; diagnostics resist shell interpolation; jq encoding safely preserves quoted and multiline routing URLs. Never reads a real user config or credential. |
| `module-eval` (since INSPR-72) | 92 sub-tests across the Home Manager and NixOS modules, run via `lib.evalModules` + stub HM and NixOS harnesses (`tests/module-eval/harness.nix`). Verifies: assertions and throws fire when they should, required options stay required, deprecations warn, Paimos literal/env URL output stays nested under `instances` without credential references, rollout/failure guards precede replacement, git include counts match declarations, and SSH authorization output and guards remain deterministic. Runs entirely at flake-eval time—no activation, real HM, or network. |

### Local dev (without nix sandbox)

```bash
nix build .#secrets-audit
./tests/secrets-audit/run-tests.sh
```

### Roadmap

- ~~Module-eval tests for HM modules~~ — **shipped (INSPR-72)**, see above.
- ~~NixOS VM integration tests~~ — **shipped for `ssh-authorized`**: `checks.<linux-system>.nixos-vm-ssh-authorized` boots a server and a client and proves sshd admits the trusted key and refuses untrusted, revoked and cross-user keys. Linux-only (needs a KVM builder with the `nixos-test` feature); on macOS the check is simply absent. It caught a real behaviour on first run — OpenSSH's per-source auth penalties — that no eval test could see. Remaining modules are still eval-only.

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
# Old (still works, emits eval warning; removed in the next MAJOR, i.e. v1.0.0 —
# an earlier revision of this line said v0.2.0, which contradicted the policy
# above and was simply wrong):
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
| **Your Paimos instance is down** | `paimos auth whoami` fails; doctor flags `paimos_auth` ✗ | Transient — wait. Local instance routing remains available. |
| **Eval-time error: "hostname could not be determined"** (since v0.1.0) | nix-rebuild fails immediately | Pass `hostname` via `extraSpecialArgs` in your homeConfigurations entry, OR set `inspr.secrets.agents.hostname = "your-host"` explicitly. |
| **Eval-time error: "defaultInstance must be a key in instances"** (since v0.1.0) | nix-rebuild fails immediately | Typo in `inspr.paimos-cli.defaultInstance`, or you set it but never declared the corresponding instance. Fix and re-eval. |
| **First fresh host: `agent-secrets` discovery returns zero** | Activation succeeds but dir is empty | Either you forgot to set `inspr.secrets.agents.encryptedRoot`, OR your repo's secrets/agents subdir is empty / not git-tracked. (Untracked files are invisible to flake eval.) |

## License

The original work in this repository is licensed under
[AGPL-3.0-only](./LICENSE). Improvements to this shared operating layer remain
inspectable under the same terms, including when a modified version is used to
provide network-accessible functionality. Independent consumer configuration,
data, and third-party components retain their own licensing boundaries.

## Status

**v0.4.2.** Extracted from a working NixOS + Home Manager fleet on 2026-05-02
and used in production since.

### Supported

| | |
|---|---|
| Nix | flakes enabled (`experimental-features = nix-command flakes`) |
| nixpkgs | `nixos-unstable` |
| Home Manager | tracking the same nixpkgs |
| Platforms | `aarch64-darwin`, `x86_64-darwin`, `x86_64-linux` |
| Not tested | `aarch64-linux` |

Versioning is SemVer over tags. Pin a tag; `main` moves.

Roadmap:
- NixOS counterparts for the remaining Home Manager modules — `ssh-authorized` has one and a VM test; `agent-secrets`, `paimos-config` and `git-identity` do not yet
- 1Password tag-export integration (Phase 2 secrets graduation)
- Remove the ignored `paimos-config` `apiKeyEnvFile` / `apiKeyVar` compatibility options after their one-release deprecation window (INSPR-225)

## Running `inspr check` on your own fleet

The CLI ships with **no fleet endpoints baked in**. Roughly thirty of its checks
are generic — nix on PATH, tailscale up, an SSH key present, git identity sane —
and run anywhere. A handful need to know *your* infrastructure, and those report
**SKIP** until you tell it, rather than failing at you.

Two ways to tell it. Copy [`examples/fleet.conf`](examples/fleet.conf):

```bash
mkdir -p ~/.config/inspr
cp examples/fleet.conf ~/.config/inspr/fleet.conf
$EDITOR ~/.config/inspr/fleet.conf
```

Or, if you use Home Manager, declare it and let the module render the file:

```nix
imports = [ inputs.inspr-modules.homeManagerModules.inspr-cli ];

inspr.cli = {
  enable = true;
  fleet = {
    headscaleUrl   = "https://headscale.example.org";
    tailnetName    = "headscale.example.org";
    paimosUrl      = "https://tracker.example.org";
    paimosInstance = "main";
    pharosUrl      = "https://pharos.example.org";
    pharosHost     = "manifest-host";
    gitIdentityName  = "Someone Example";
    gitIdentityEmail = "someone@example.com";
  };
};
```

### The check worth understanding

`tailscale_control_url` compares your tailnet's name against `tailnetName`. It
looks redundant next to "is tailscale up" — it isn't. A host can be up, logged
in, and reachable while pointed at **Tailscale SaaS instead of your own
Headscale**, and every other check passes in that state. Comparing the name is
the only thing that catches it. That check exists because it happened.

Nothing in this file is a credential. Every value is an endpoint or public
identity metadata, and the rendered file is world-readable; authentication
lives in the OS keyring.

## Checking that your wiring actually resolves

Vendoring the doctrine is easy to get *almost* right, and almost-right fails
silently: a dangling `@`-ref loads nothing without complaint, and a broken
command symlink means the command simply does not appear — you type it, get
nothing, and assume you misremembered the name.

### Setting it up — the part that was missing

The check assumes a specific layout, and until now nothing told you how to
create it. From your repository root:

```bash
# 1. Vendor the doctrine as a submodule at ./doctrine, pinned to a tag.
git submodule add https://github.com/inspr-at/inspr-modules.git doctrine
git -C doctrine checkout v0.4.2
git add doctrine .gitmodules

# 2. Load the kernel from your agent instruction file. @-refs resolve from the
#    REPO ROOT, not from the file that contains them.
printf '@./doctrine/docs/AGENTS-KERNEL.md\n' >> CLAUDE.md

# 3. Optionally expose the doctrine's slash commands as symlinks.
mkdir -p .claude/commands
ln -s ../../doctrine/commands/dev.md .claude/commands/dev.md   # repeat per command you want

# 4. Run it.
./doctrine/scripts/doctrine-check.sh
```

`AGENTS.md` and `AGENTS-*.md` at the root are also scanned. Anything under
`.claude/commands/` (or `+agents/commands/`) is scanned too, including
`@`-refs *inside* those command files.

Environment knobs, all optional:

| variable | default | meaning |
|---|---|---|
| `DOCTRINE_MAX_BEHIND` | `3` | how many commits behind canonical a pin may be before it fails |
| `DOCTRINE_UPSTREAMS` | `inspr-modules\|inspr-doctrine-private` | which upstreams count as doctrine for the multi-path check |
| `DOCTRINE_STRICT` | `0` | `1` makes "could not verify" (e.g. no network) exit 1 instead of reporting INCOMPLETE |

The check **skips** assertions whose surface does not exist rather than
failing them, so a green run on an empty repository proves nothing. Read the
output; a `∘` line is a skip, not a pass.

Five assertions: every `@`-ref resolves (including inside command files); every
command is a live symlink (a regular file there is a copy, and copies drift);
the doctrine pins are not far behind canonical; any declared command list
matches what is wired; and where a repository consumes the same doctrine
through more than one path (a submodule *and* a flake input), those paths agree
bit-for-bit — a split there means agent sessions and hosts follow different
rules.

Add it to CI with [`examples/doctrine-check.yml`](examples/doctrine-check.yml).
Note `submodules: recursive` in the checkout step — without it the check has
nothing to resolve against and will report everything as broken.

`--warn` downgrades failures to advisory, for adopting it on a repo that is not
clean yet.

### About `leak-guard.sh`

Also in `scripts/`, and worth being clear about: **it is this repository's own
publication lint, not a general secret scanner.** Its `PATTERNS` name this
project's hosts, domains and paths. Run unchanged in your repository it would
protect this maintainer's identity better than yours.

If you want the mechanism — fail-closed, whole-tree, redacted output, reviewed
allowlist — copy the script, rewrite `PATTERNS` for what *you* must never
publish, keep it at `scripts/leak-guard.sh` (it excludes itself by that path),
and add a `.leak-guard-allow` at your root. There is no flake output for it
and no `--help`; that is a deliberate scope limit, not an oversight, and it is
why the security policy calls it an incomplete control rather than a guarantee.
