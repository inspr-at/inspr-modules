# inspr-modules

Reusable Home Manager modules + utilities from the [INSPR](https://inspr.at) initiative.

> *"Where your inspirations live."* — democratize software development by giving anyone the same primitives Markus uses on his own fleet.

## What's here

### Home Manager modules

| Module | Namespace | What it does |
|---|---|---|
| `agent-secrets` | `inspr.secrets.agents` | Materialize agenix-encrypted env files into a per-user "agent-exception" directory at HM activation. Pairs with the env-file pattern (`KEY=value`) for `set -a; source $FILE` consumers. |
| `git-identity` | `inspr.git-identity` | Multi-identity git config with both `gitdir:` AND `hasconfig:remote.*.url:` includeIf rules. The repo's own remote URL picks the identity automatically — no per-host directory list to maintain. |
| `paimos-config` | `inspr.paimos-cli` | Auto-bootstrap `~/.paimos/config.yaml` from agent-secrets-materialized API key files. After this, [paimos-cli](https://github.com/markus-barta/paimos) is ready to use without manual `paimos auth login` per host. |
| `default` | (aggregate) | Imports all three above. Consumers wanting à-la-carte should import individual modules. |

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
    instances.mine = {
      url = "https://your-paimos.example.com";
      apiKeyEnvFile = "/run/agenix/your-paimos-api-key";  # or wherever
      apiKeyVar = "PAIMOS_API_KEY";
    };
  };
}
```

## Architecture notes

These modules emerged from the INSPR onboarding sessions documented in the (private) `inspr` umbrella repo. The design pattern — Pattern β — separates:

- **Universal mechanics** (this library: how to materialize secrets, how to compose git includeIfs, how to write a paimos config)
- **Per-context values** (your flake: identities, instance URLs, fleet patterns)

A "context flake" is anything that consumes inspr-modules + provides its own values: Markus's personal `nixcfg`, his BYTEPOETS work flake, his family flake, future paid-product flakes — each declares its own identity, hosts, and secrets, and gets the rest for free.

## License

MIT — deliberately permissive. This is a *library*; restrictive licenses on infrastructure modules would discourage exactly the adoption the mission depends on.

## Status

v0.1.0 — extracted from `markus-barta/nixcfg` on 2026-05-02. Tested on:
- macOS workstation (M5, aarch64-darwin)
- macOS workstation (imac0, x86_64-darwin)
- NixOS server (csb0, x86_64-linux)

via `inspr-doctor` (in the [inspr](https://github.com/markus-barta/inspr) umbrella repo).

Roadmap:
- NixOS-equivalent modules (currently HM-only — server-side `system_agenix_decrypted` is a doctor check, not yet a module here)
- 1Password tag-export integration (Phase 2 secrets graduation)
- Cross-platform paimos-cli config (Linux + macOS verified; Windows untested)
