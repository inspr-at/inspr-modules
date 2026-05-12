# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║         INSPR — Per-atelier outbound git credentials (HM module)             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Declarative per-atelier outbound git credentials, forge-agnostic, scaling
# from solo-hobbyist to enterprise. Companion to:
#   inspr.ssh.authorized   — inbound trust (~/.ssh/authorized_keys)
#   inspr.ssh.fleet        — outbound SSH-to-fleet
#   inspr.secrets.agents   — per-host agent secrets via agenix
#
# This module fills the gap surfaced 2026-05-12 (Day-9 of the INSPR rollout)
# when neither m5 nor msbp could push to BYTEPOETS/bpnixcfg without
# hand-rolled per-host wiring. Full design rationale + 4-tier scaling story
# in the proposal doc: ~/Code/inspr/proposals/git-atelier-credentials.md.
#
# Doctrine
# ────────
# Substrate-portable primitives first; forge-specific richness as opt-in
# extras. INSPR's git layer must survive forge migration via config-level
# change only — Forgejo / Codeberg / GitLab / Gitea / sourcehut / bare-SSH
# all support the universal primitives (per-repo deploy key, per-host user
# SSH key, access tokens). GitHub Apps and analogous forge-rich primitives
# are non-portable by design and stay opt-in escape hatches.
#
# Strategies (MVP shows A; B and C are option-typed but throw on use —
# INSPR-168 follow-ups will implement them):
#   A. Per-repo SSH deploy key  — least-privilege, never-rotate, per-host
#                                  per-repo scope. Best for SERVERS pushing
#                                  their own config (Markus's msbp pattern).
#   B. Per-host user SSH key    — host-level identity, account-federated.
#                                  Best for WORKSTATIONS.
#   C. Bot user / access token  — covers HTTPS git + gh CLI + GraphQL.
#                                  Best for multi-repo automation when
#                                  rotation is the point (otherwise prefer A).
#
# Usage — Strategy A (per-repo deploy key, the MVP-implemented strategy):
#
#   inspr.git.atelier.bytepoets = {
#     enable = true;
#     forge = {
#       kind  = "github";              # github | forgejo | gitlab | gitea | sourcehut | ssh
#       url   = "https://github.com";  # full origin URL, used for known_hosts + alias
#       owner = "BYTEPOETS";           # org/user/group on that forge
#     };
#     credentials.deployKeys.bpnixcfg = {
#       privateKeyPath = "/run/agenix/miniserver-bp-bpnixcfg-deploy-key";
#       pubKey = "ssh-ed25519 AAA…";   # documentation field (audit only)
#     };
#   };
#
# Consumer is responsible for:
#   - agenix declaration in secrets/secrets.nix
#   - age.secrets.<name> system-level wiring (file → /run/agenix/<name> with
#     owner=<user>, mode=0600)
#   - One-time forge-side action: register the matching public key as a
#     deploy key with write access on the target repo
#
# This module renders (at HM activation):
#   - ~/.ssh/config matchBlock(s) — one per deploy key, with HostKeyAlias
#     so all aliased paths share known_hosts entries for the forge
#   - ~/.gitconfig url.insteadOf rewrites — both HTTPS and direct-SSH forms
#     of the repo URL route through the aliased SSH host
#   - ~/.ssh/known_hosts.d/inspr-git-atelier-<name> — well-known public host
#     keys for forges with baked-in defaults (currently github.com).
#     Self-hosted forges: pass extraKnownHosts.
#
# Multi-atelier per host: declare multiple keys in the attrset; each gets
# its own SSH alias namespace and url.insteadOf rewrite.
#
# License: MIT — see inspr-modules/flake.nix.
#
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.inspr.git.atelier;

  # ── Forge URL → host (strip scheme + trailing slash) ────────────────────
  forgeHost =
    forgeUrl:
    let
      noScheme = lib.removePrefix "http://" (lib.removePrefix "https://" forgeUrl);
    in
      lib.removeSuffix "/" noScheme;

  # ── Well-known public host keys per forge ───────────────────────────────
  # Verified against vendor-published fingerprints. Built-in coverage for
  # forges with stable, well-documented host keys. Self-hosted forges or
  # rotated keys: consumer supplies via `forge.extraKnownHosts`.
  #
  # Sources:
  #   github.com: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
  #   codeberg.org: https://docs.codeberg.org/security/ssh-fingerprint/
  builtinKnownHosts = {
    "github.com" = [
      "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
      "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
      "github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk="
    ];
    "codeberg.org" = [
      "codeberg.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIVIWFsa1WVjEnPbBoy7jzqr2NDXcAEEZIvVqYE9CpcL"
      "codeberg.org ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBL2pDxWr18SoiDJCGZ5LmxPygTlPu+cCKSkpqkvCyQzl5xmIMeKNdfdBpfbCGDPoZQghePzFZkKJNR/v9Win3oc="
      "codeberg.org ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDPNqQXNHQiTQv2HFszYI/dKjEWaPNzPCgsoYjlBkN0OqdAdcJFkGB3hSpwlPB6PUtoIp08ekUtP2Es2QcBp33ZsHJ0gnNJYRetSWAU9PObUJxJiKsTLh0Nz5g70RM4o5N1HmckiBoX/JS6BoaWBdmsRfvFTBpiqOaJ4LtmcMz+L2cTYjlw/cGlV6mQ4P7c5VAhU9ZQ7ARFI83lN/h0sFotbHnoSk9eAGmlbcOmrh21Zg5cqzNS0e10pY4eFVqmIO6LJYpDh8VfJOAtUKEEZ97f0OYIlbeMNZRzKHCAxF6QikXKv+QzTpFEpUEAuJM77t6vyHIqcHi6sLgodIIPI9b5"
    ];
  };

  # ── Per-deploy-key rendering ────────────────────────────────────────────
  # For each (atelierName, repoName, deployKey) tuple, produce:
  #   - SSH match block keyed by alias `<forgeHost>-<atelier>-<repo>`
  #   - git url.insteadOf rewrite mapping HTTPS + direct-SSH forms to the
  #     aliased SSH host
  mkDeployKeyAlias = atelierName: repoName: "${forgeHost cfg.${atelierName}.forge.url}-${atelierName}-${repoName}";

  mkDeployKeyMatchBlock =
    atelierName: atelier: repoName: deployKey:
    let
      host = forgeHost atelier.forge.url;
      alias = "${host}-${atelierName}-${repoName}";
    in {
      ${alias} = {
        hostname       = host;
        user           = "git";
        identityFile   = deployKey.privateKeyPath;
        identitiesOnly = true;
        extraOptions = {
          # Look up host key under the canonical host name (forge host)
          # rather than the alias. Lets one known_hosts entry cover ALL
          # aliased SSH paths to this forge.
          HostKeyAlias = host;
        } // lib.optionalAttrs atelier.manageKnownHosts {
          # Read user-managed known_hosts file too, so the forge's host
          # keys (rendered to known_hosts.d below) are trusted.
          UserKnownHostsFile = "~/.ssh/known_hosts ~/.ssh/known_hosts.d/inspr-git-atelier-${atelierName}";
        };
      };
    };

  mkDeployKeyUrlRewrite =
    atelierName: atelier: repoName: _deployKey:
    let
      host = forgeHost atelier.forge.url;
      alias = "${host}-${atelierName}-${repoName}";
      owner = atelier.forge.owner;
    in {
      "git@${alias}:${owner}/${repoName}".insteadOf = [
        "${atelier.forge.url}/${owner}/${repoName}"
        "${atelier.forge.url}/${owner}/${repoName}.git"
        "git@${host}:${owner}/${repoName}"
        "git@${host}:${owner}/${repoName}.git"
      ];
    };

  # ── Validate strategy choice + collect rendered config per atelier ──────
  validateAtelier =
    atelierName: atelier:
    let
      hasDeployKeys = atelier.credentials.deployKeys != { };
      hasUserKey    = atelier.credentials.userKey != null;
      hasToken      = atelier.credentials.token != null;
    in
    if !(hasDeployKeys || hasUserKey || hasToken)
    then throw ''
      inspr.git.atelier."${atelierName}": no credentials declared.
      Set at least one of:
        - credentials.deployKeys.<repo> (Strategy A, MVP)
        - credentials.userKey           (Strategy B, throws — INSPR-168 follow-up)
        - credentials.token             (Strategy C, throws — INSPR-168 follow-up)
    ''
    else if hasUserKey then throw ''
      inspr.git.atelier."${atelierName}".credentials.userKey: Strategy B
      (per-host user SSH key) is option-typed but not yet implemented in
      the MVP. See INSPR-168 follow-up. Use Strategy A (deployKeys) for
      now, or contribute the impl.
    ''
    else if hasToken then throw ''
      inspr.git.atelier."${atelierName}".credentials.token: Strategy C
      (PAT / bot-user token) is option-typed but not yet implemented in
      the MVP. See INSPR-168 follow-up. Use Strategy A (deployKeys) for
      now, or contribute the impl.
    ''
    else atelier;

  # Forge-kind support gate. MVP supports any forge that uses ssh git@
  # transport with deploy keys (all of them in practice). The kind field
  # is captured for documentation + future forge-specific rendering
  # (e.g., GitHub Apps under Strategy G1).
  validateForgeKind =
    atelierName: atelier:
    let supportedForMvp = [ "github" "forgejo" "gitlab" "gitea" "sourcehut" "ssh" ]; in
    if !(lib.elem atelier.forge.kind supportedForMvp)
    then throw ''
      inspr.git.atelier."${atelierName}".forge.kind = "${atelier.forge.kind}":
      not recognized. Supported (MVP): ${lib.concatStringsSep ", " supportedForMvp}.
    ''
    else atelier;

  # ── Per-atelier renderers (top-level config aggregators) ────────────────
  enabledAteliers = lib.filterAttrs (_: a: a.enable) cfg;

  renderedMatchBlocks = lib.mkMerge (
    lib.flatten (
      lib.mapAttrsToList (
        atelierName: atelier:
          let _ = validateAtelier atelierName (validateForgeKind atelierName atelier); in
          lib.mapAttrsToList
            (repoName: dk: mkDeployKeyMatchBlock atelierName atelier repoName dk)
            atelier.credentials.deployKeys
      ) enabledAteliers
    )
  );

  renderedUrlRewrites = lib.mkMerge (
    lib.flatten (
      lib.mapAttrsToList (
        atelierName: atelier:
          lib.mapAttrsToList
            (repoName: dk: mkDeployKeyUrlRewrite atelierName atelier repoName dk)
            atelier.credentials.deployKeys
      ) enabledAteliers
    )
  );

  # known_hosts files (one per atelier that opts into management).
  renderedKnownHosts = lib.listToAttrs (
    lib.concatLists (
      lib.mapAttrsToList (
        atelierName: atelier:
          if atelier.manageKnownHosts && atelier.credentials.deployKeys != { }
          then [{
            name = ".ssh/known_hosts.d/inspr-git-atelier-${atelierName}";
            value = {
              text =
                let
                  host = forgeHost atelier.forge.url;
                  baked = builtinKnownHosts.${host} or [ ];
                in ''
                  # Managed by inspr.git.atelier."${atelierName}" — do not hand-edit.
                  # Forge: ${atelier.forge.kind} @ ${atelier.forge.url} (owner: ${atelier.forge.owner})
                  ${lib.concatStringsSep "\n" baked}
                  ${lib.concatStringsSep "\n" atelier.forge.extraKnownHosts}
                '';
            };
          }]
          else [ ]
      ) enabledAteliers
    )
  );

  # Warn if manageKnownHosts is true but no built-in keys exist AND no extra
  # keys provided — would render an empty file, breaking SSH host verification.
  knownHostsWarnings = lib.flatten (
    lib.mapAttrsToList (
      atelierName: atelier:
        let
          host = forgeHost atelier.forge.url;
          baked = builtinKnownHosts.${host} or [ ];
          hasExtras = atelier.forge.extraKnownHosts != [ ];
        in
        if atelier.manageKnownHosts && atelier.credentials.deployKeys != { }
           && baked == [ ] && !hasExtras
        then [''
          inspr.git.atelier."${atelierName}": manageKnownHosts = true but no
          built-in host keys for "${host}" AND forge.extraKnownHosts is empty.
          SSH will reject the first connection. Either supply
          forge.extraKnownHosts or set manageKnownHosts = false and manage
          ~/.ssh/known_hosts yourself.
        '']
        else [ ]
    ) enabledAteliers
  );
in
{
  options.inspr.git.atelier = lib.mkOption {
    default = { };
    description = ''
      Per-atelier outbound git credentials. Each named atelier maps to one
      forge owner (org/user/group) and declares one or more credential
      strategies for hosts to push/fetch through. See module header for the
      full design rationale + 4-tier scaling story.
    '';
    type = lib.types.attrsOf (lib.types.submodule (
      { name, ... }: {
        options = {
          enable = lib.mkEnableOption "this atelier's credential materialization";

          forge = {
            kind = lib.mkOption {
              type = lib.types.enum [ "github" "forgejo" "gitlab" "gitea" "sourcehut" "ssh" ];
              description = ''
                Forge family. Currently informational + used to look up
                built-in known_hosts (github.com, codeberg.org); future
                forge-specific renderings (e.g. Strategy G1 GitHub Apps)
                will key off this.
              '';
              example = "github";
            };
            url = lib.mkOption {
              type = lib.types.str;
              description = ''
                Forge base URL — used to derive the SSH host + the canonical
                HTTPS clone URL pattern that gets url.insteadOf rewritten.
                Strip trailing slash; HTTPS scheme assumed for forges, "ssh"
                kind uses bare hostnames.
              '';
              example = "https://github.com";
            };
            owner = lib.mkOption {
              type = lib.types.str;
              description = ''
                Org / user / group on that forge that owns the repos this
                atelier covers.
              '';
              example = "BYTEPOETS";
            };
            extraKnownHosts = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = ''
                Additional known_hosts entries (full OpenSSH format lines)
                appended to the managed known_hosts.d/inspr-git-atelier-<name>
                file. Required for self-hosted forges; optional for forges
                with built-in keys (github.com, codeberg.org).
              '';
              example = lib.literalExpression ''
                [
                  "git.bytepoets.com ssh-ed25519 AAAA…"
                ]
              '';
            };
          };

          manageKnownHosts = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              If true, render a managed known_hosts file containing the
              forge's host keys (built-in for github.com/codeberg.org;
              consumer-supplied via forge.extraKnownHosts for others) and
              wire it into the relevant SSH match blocks.
            '';
          };

          rewriteUrls = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              If true, render url.insteadOf rewrites so canonical HTTPS
              clone URLs transparently route through the aliased SSH host
              with the right deploy key.
            '';
          };

          credentials = {
            deployKeys = lib.mkOption {
              default = { };
              description = ''
                Strategy A — per-repo SSH deploy keys. Each entry's key is
                the repo name (within forge.owner); value declares the
                runtime path of the agenix-decrypted private key + the
                public key for documentation/audit.
              '';
              type = lib.types.attrsOf (lib.types.submodule {
                options = {
                  privateKeyPath = lib.mkOption {
                    type = lib.types.str;
                    description = ''
                      Filesystem path to the decrypted private SSH key.
                      Consumer is responsible for materializing this via
                      `age.secrets.<name>` (NixOS-level) with owner=<user>
                      and mode=0600. Typical value: /run/agenix/<name>.
                    '';
                    example = "/run/agenix/host-bp-bpnixcfg-deploy-key";
                  };
                  pubKey = lib.mkOption {
                    type = lib.types.str;
                    description = ''
                      Public half of the SSH keypair, in OpenSSH single-line
                      format. Documentation + audit field only — not used by
                      the module at runtime. Recommended: include comment
                      identifying host + repo + date.
                    '';
                    example = "ssh-ed25519 AAAAC3Nz… bp-bpnixcfg-deploy@msbp 2026-05-12";
                  };
                };
              });
              example = lib.literalExpression ''
                {
                  bpnixcfg = {
                    privateKeyPath = "/run/agenix/msbp-bp-bpnixcfg-deploy-key";
                    pubKey = "ssh-ed25519 AAAA…";
                  };
                }
              '';
            };

            userKey = lib.mkOption {
              default = null;
              description = ''
                Strategy B — per-host user SSH key (account-federated).
                **Not yet implemented in MVP** — option-typed for forward
                compatibility; throws at eval time if used. See INSPR-168
                follow-ups.
              '';
              type = lib.types.nullOr (lib.types.submodule {
                options = {
                  privateKeyPath = lib.mkOption { type = lib.types.str; };
                  pubKey = lib.mkOption { type = lib.types.str; };
                };
              });
            };

            token = lib.mkOption {
              default = null;
              description = ''
                Strategy C — bot user / access token via git credential
                helper (HTTPS, also covers gh CLI + GraphQL API).
                **Not yet implemented in MVP** — option-typed for forward
                compatibility; throws at eval time if used. See INSPR-168
                follow-ups.
              '';
              type = lib.types.nullOr (lib.types.submodule {
                options = {
                  tokenPath = lib.mkOption { type = lib.types.str; };
                  botUser = lib.mkOption { type = lib.types.str; default = "x-access-token"; };
                };
              });
            };
          };
        };
      }
    ));
  };

  config = lib.mkIf (enabledAteliers != { }) {
    programs.ssh = {
      enable = true;
      matchBlocks = renderedMatchBlocks;
    };

    programs.git = lib.mkIf (
      lib.any (a: a.rewriteUrls && a.credentials.deployKeys != { })
              (lib.attrValues enabledAteliers)
    ) {
      enable = lib.mkDefault true;
      extraConfig.url = renderedUrlRewrites;
    };

    home.file = renderedKnownHosts;

    warnings = knownHostsWarnings;
  };
}
