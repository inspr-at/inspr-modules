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
# Strategies (A + B implemented; C option-typed but throws on use —
# INSPR-170 lands Strategy B; Strategy C remains an INSPR-168 follow-up):
#   A. Per-repo SSH deploy key  — least-privilege, never-rotate, per-host
#                                  per-repo scope. Best for SERVERS pushing
#                                  their own config (one repo, one key).
#   B. Per-host user SSH key    — account-federated identity (one key per
#                                  host × identity, registered on the GH
#                                  account, inherits all repo access + org
#                                  memberships). Best for WORKSTATIONS that
#                                  need push/pull across many repos under
#                                  one identity, and the canonical answer
#                                  to the recurring "this machine doesn't
#                                  have permission to that service" friction.
#   C. Bot user / access token  — covers HTTPS git + gh CLI + GraphQL.
#                                  Best for multi-repo automation when
#                                  rotation is the point (otherwise prefer B).
#
# Per-atelier commit author identity (independent of credential strategy):
#   inspr.git.atelier.<name>.git.{userName, userEmail, workspacePath} sets
#   user.name + user.email scoped to either a workspace path (via gitdir:
#   includeIf) or the forge-owner remote URL pattern (via hasconfig:
#   includeIf, git 2.36+). So commits to BYTEPOETS repos can attribute to
#   bytepoets-mba while commits to markus-barta repos attribute to
#   markus-barta — automatic, declarative, no per-repo `git config` toil.
#
# Usage — Strategy A (per-repo deploy key; servers, narrow scope):
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
# Usage — Strategy B (per-host user SSH key; workstations, federated access):
#
#   inspr.git.atelier.bytepoets = {
#     enable = true;
#     forge = {
#       kind  = "github";
#       url   = "https://github.com";
#       owner = "BYTEPOETS";
#     };
#     credentials.userKey = {
#       privateKeyPath = "/run/agenix/m5-bytepoets-userkey";
#       pubKey = "ssh-ed25519 AAA…";   # registered on bytepoets-mba account
#     };
#     git = {
#       userName  = "bytepoets-mba";
#       userEmail = "mba@bytepoets.com";
#       workspacePath = "~/Code/BYTEPOETS";   # commits in this dir attribute to bytepoets-mba
#     };
#   };
#
# After rebuild on m5/imac0/imacw, any `git clone git@github.com:BYTEPOETS/<any>.git`
# or `git clone https://github.com/BYTEPOETS/<any>.git` is transparently rewritten
# to `git@git-bytepoets:BYTEPOETS/<any>.git`, authenticated by m5's bytepoets userKey,
# with commits in that workspace attributed to bytepoets-mba.
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
  options,
  pkgs,
  ...
}:

let
  cfg = config.inspr.git.atelier;

  # HM ≥25.05 introduces `programs.ssh.enableDefaultConfig` and warns when
  # `programs.ssh.enable = true` without explicit opt-out. Older HM versions
  # don't have the option — so we conditionally set it only when the
  # consumer's HM exposes it. INSPR-172 deprecation cleanup, 2026-05-13.
  hasEnableDefaultConfig =
    options ? programs && options.programs ? ssh && options.programs.ssh ? enableDefaultConfig;

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

  # ── Validate strategy choice + forge kind (eager throws) ────────────────
  # validateAtelier throws if the atelier's credential strategy isn't
  # actually implementable. Forced eagerly via builtins.seq from the
  # renderers so the throw surfaces at config-eval time (real HM switch
  # or eval-modules test), not silently lost.
  validateAtelier =
    atelierName: atelier:
    let
      hasDeployKeys = atelier.credentials.deployKeys != { };
      hasUserKey    = atelier.credentials.userKey != null;
      hasToken      = atelier.credentials.token != null;
    in
    if hasToken then throw ''
      inspr.git.atelier."${atelierName}".credentials.token: Strategy C
      (PAT / bot-user token) is option-typed but not yet implemented.
      See INSPR-168 follow-up. Use Strategy A (deployKeys) or Strategy B
      (userKey) for now, or contribute the impl.
    ''
    else if !hasDeployKeys && !hasUserKey then throw ''
      inspr.git.atelier."${atelierName}": no credentials declared.
      Set at least one of:
        - credentials.deployKeys.<repo> (Strategy A — per-repo, servers)
        - credentials.userKey           (Strategy B — per-identity, workstations)
        - credentials.token             (Strategy C — throws, INSPR-168 follow-up)
    ''
    else true;  # sentinel value — non-null so callers can `builtins.seq` it

  # Forge-kind support gate. MVP supports any forge that uses ssh git@
  # transport with deploy keys (all enum values in practice). The kind
  # field is captured for documentation + future forge-specific rendering
  # (e.g., GitHub Apps under Strategy G1).
  validateForgeKind =
    atelierName: atelier:
    let supportedForMvp = [ "github" "forgejo" "gitlab" "gitea" "sourcehut" "ssh" ]; in
    if !(lib.elem atelier.forge.kind supportedForMvp)
    then throw ''
      inspr.git.atelier."${atelierName}".forge.kind = "${atelier.forge.kind}":
      not recognized. Supported (MVP): ${lib.concatStringsSep ", " supportedForMvp}.
    ''
    else true;

  # ── Per-atelier renderers ────────────────────────────────────────────────
  # Direct attrset construction via lib.listToAttrs — avoids lib.mkMerge,
  # which doesn't unwrap when the target option is `unspecified`-typed
  # (e.g., in test stubs; harmless but breaks deep-eq assertions).
  enabledAteliers = lib.filterAttrs (_: a: a.enable) cfg;

  renderedMatchBlocks = lib.listToAttrs (
    lib.concatLists (
      lib.mapAttrsToList (atelierName: atelier:
        # Force validation BEFORE rendering this atelier's contributions.
        # builtins.seq forces its first arg, then returns its second; a
        # throw in validateAtelier/validateForgeKind propagates here.
        builtins.seq
          (validateAtelier atelierName atelier)
          (builtins.seq
            (validateForgeKind atelierName atelier)
            (lib.mapAttrsToList (repoName: dk:
              let
                host = forgeHost atelier.forge.url;
                alias = "${host}-${atelierName}-${repoName}";
              in {
                name = alias;
                # HM ≥25.05: `programs.ssh.settings` replaces deprecated
                # `matchBlocks`. Upstream OpenSSH directives (HostKeyAlias,
                # UserKnownHostsFile) sit directly under the per-host attrset
                # using their PascalCase names, alongside HM-camelCase keys.
                value = {
                  hostname       = host;
                  user           = "git";
                  identityFile   = dk.privateKeyPath;
                  identitiesOnly = true;
                  # Look up host key under canonical forge host name rather
                  # than the alias. One known_hosts entry covers ALL aliased
                  # SSH paths to this forge.
                  HostKeyAlias   = host;
                } // lib.optionalAttrs atelier.manageKnownHosts {
                  UserKnownHostsFile = "~/.ssh/known_hosts ~/.ssh/known_hosts.d/inspr-git-atelier-${atelierName}";
                };
              }
            ) atelier.credentials.deployKeys)
          )
      ) enabledAteliers
    )
  );

  renderedUrlRewrites = lib.listToAttrs (
    lib.concatLists (
      lib.mapAttrsToList (atelierName: atelier:
        if !atelier.rewriteUrls then [ ] else
        lib.mapAttrsToList (repoName: _dk:
          let
            host = forgeHost atelier.forge.url;
            alias = "${host}-${atelierName}-${repoName}";
            owner = atelier.forge.owner;
          in {
            name = "git@${alias}:${owner}/${repoName}";
            value.insteadOf = [
              "${atelier.forge.url}/${owner}/${repoName}"
              "${atelier.forge.url}/${owner}/${repoName}.git"
              "git@${host}:${owner}/${repoName}"
              "git@${host}:${owner}/${repoName}.git"
            ];
          }
        ) atelier.credentials.deployKeys
      ) enabledAteliers
    )
  );

  # ── Strategy B renderers ─────────────────────────────────────────────────
  # One SSH alias per atelier (not per-repo as in Strategy A). The alias
  # name is `git-<atelierName>` — short, identity-scoped, persona-clear.
  # URL rewrites are owner-prefix scoped: `git@github.com:OWNER/` →
  # `git@git-<atelier>:OWNER/`. Git's prefix-match semantics make this
  # cover every repo under that owner automatically (no per-repo wiring).
  #
  # Co-existence with Strategy A: if an atelier declares BOTH a userKey
  # and deployKeys for specific repos, git's "longest insteadOf match
  # wins" rule routes deploy-key repos through their narrow alias and
  # everything-else-under-the-owner through the userKey alias.
  enabledUserKeyAteliers = lib.filterAttrs
    (_: a: a.credentials.userKey != null) enabledAteliers;

  renderedUserKeyMatchBlocks = lib.listToAttrs (
    lib.mapAttrsToList (atelierName: atelier:
      let
        host = forgeHost atelier.forge.url;
        alias = "git-${atelierName}";
      in
        builtins.seq
          (validateAtelier atelierName atelier)
          (builtins.seq
            (validateForgeKind atelierName atelier)
            {
              name = alias;
              # HM ≥25.05: see comment in renderedMatchBlocks above.
              value = {
                hostname       = host;
                user           = "git";
                identityFile   = atelier.credentials.userKey.privateKeyPath;
                identitiesOnly = true;
                HostKeyAlias   = host;
              } // lib.optionalAttrs atelier.manageKnownHosts {
                UserKnownHostsFile =
                  "~/.ssh/known_hosts ~/.ssh/known_hosts.d/inspr-git-atelier-${atelierName}";
              };
            })
    ) enabledUserKeyAteliers
  );

  renderedUserKeyUrlRewrites = lib.listToAttrs (
    lib.mapAttrsToList (atelierName: atelier:
      let
        host = forgeHost atelier.forge.url;
        alias = "git-${atelierName}";
        owner = atelier.forge.owner;
      in {
        name = "git@${alias}:${owner}/";
        value.insteadOf = [
          "${atelier.forge.url}/${owner}/"
          "git@${host}:${owner}/"
        ];
      }
    ) (lib.filterAttrs (_: a: a.rewriteUrls) enabledUserKeyAteliers)
  );

  # ── Per-atelier author identity renderers ────────────────────────────────
  # Each atelier with git.userName or git.userEmail set produces:
  #   1. A standalone gitconfig fragment at
  #      ~/.config/git/inspr-atelier-<name>.gitconfig containing [user] entries
  #   2. An includeIf entry in the main gitconfig that loads that fragment
  #      conditionally, scoped by either:
  #      - `gitdir:<workspacePath>/**` (path-based, preferred when set —
  #         intuitive, predictable, matches even non-INSPR clones in that dir)
  #      - `hasconfig:remote.*.url:**<forgeHost>*<owner>/**` (URL-based fallback,
  #         git 2.36+ — auto-matches any clone of that owner's repos regardless
  #         of which directory they live in)
  enabledIdentityAteliers = lib.filterAttrs
    (_: a: a.git.userName != null || a.git.userEmail != null) enabledAteliers;

  identityFragmentPath = atelierName:
    ".config/git/inspr-atelier-${atelierName}.gitconfig";

  renderedIdentityFragments = lib.listToAttrs (
    lib.mapAttrsToList (atelierName: atelier: {
      name = identityFragmentPath atelierName;
      value.text =
        let
          name  = atelier.git.userName;
          email = atelier.git.userEmail;
        in ''
          # Managed by inspr.git.atelier."${atelierName}" — do not hand-edit.
          # Scoped via includeIf in the main gitconfig (gitdir-based if
          # workspacePath set, else remote-URL-based).
          [user]
          ${lib.optionalString (name  != null) "  name = ${name}"}
          ${lib.optionalString (email != null) "  email = ${email}"}
        '';
    }) enabledIdentityAteliers
  );

  renderedIdentityIncludes = lib.mapAttrsToList (atelierName: atelier:
    let
      host  = forgeHost atelier.forge.url;
      owner = atelier.forge.owner;
      fragPath = "~/${identityFragmentPath atelierName}";
    in
      if atelier.git.workspacePath != null
      then {
        condition = "gitdir:${atelier.git.workspacePath}/";
        path      = fragPath;
      }
      else {
        # hasconfig requires git 2.36+ (April 2022). Pattern matches any
        # remote URL containing both the forge host AND the owner — works
        # for HTTPS, plain SSH, and post-rewrite alias SSH alike.
        condition = "hasconfig:remote.*.url:*${host}*${owner}/*";
        path      = fragPath;
      }
  ) enabledIdentityAteliers;

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

          git = {
            userName = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Per-atelier git author name (`user.name`). When set, a
                gitconfig fragment is rendered and `includeIf`-loaded so
                commits in scope of this atelier are authored under this
                identity. Scope is determined by `workspacePath` (gitdir
                match — preferred when set) or by the forge-owner remote
                URL pattern (hasconfig match, git 2.36+).
              '';
              example = "bytepoets-mba";
            };
            userEmail = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Per-atelier git author email (`user.email`). Same scoping
                semantics as `userName`.
              '';
              example = "mba@bytepoets.com";
            };
            workspacePath = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Optional. When set, the per-atelier author identity is
                scoped to repos under this directory via
                `includeIf "gitdir:<path>/"`. Path-based scoping is the
                preferred form: intuitive, predictable, and works on git
                versions older than 2.36.

                When null, scoping falls back to remote-URL matching
                (`includeIf "hasconfig:remote.*.url:*<forgeHost>*<owner>/*"`)
                which requires git 2.36+ but auto-matches any clone of an
                atelier-owner's repos regardless of directory.

                Tilde (`~`) is honored by git, so `~/Code/BYTEPOETS` works.
              '';
              example = "~/Code/BYTEPOETS";
            };
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
                Strategy B — per-host user SSH key (account-federated). One
                key per (host × identity), registered on the forge user
                account; inherits all repo access + org memberships granted
                to that user. The canonical answer to the recurring "this
                machine doesn't have permission to that service" friction.

                Renders an SSH alias `git-<atelierName>` with `IdentityFile`
                pointing at the agenix-decrypted privkey, plus an owner-glob
                URL rewrite (`git@<host>:OWNER/` → `git@git-<atelier>:OWNER/`)
                so every repo under the atelier's `forge.owner` is reached
                through this key automatically.
              '';
              type = lib.types.nullOr (lib.types.submodule {
                options = {
                  privateKeyPath = lib.mkOption {
                    type = lib.types.str;
                    description = ''
                      Filesystem path to the decrypted private SSH key.
                      Consumer is responsible for materializing this via
                      `age.secrets.<name>` (NixOS-level) with owner=<user>
                      and mode=0600. Typical value: /run/agenix/<name>.
                    '';
                    example = "/run/agenix/m5-bytepoets-userkey";
                  };
                  pubKey = lib.mkOption {
                    type = lib.types.str;
                    description = ''
                      Public half of the SSH keypair, in OpenSSH single-line
                      format. Documentation + audit field only — not used by
                      the module at runtime. Recommended: include comment
                      identifying host + identity + date so the GH-side key
                      listing stays auditable.
                    '';
                    example = "ssh-ed25519 AAAAC3Nz… m5-bytepoets-userkey@bytepoets-mba 2026-05-12";
                  };
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

  config = lib.mkIf (enabledAteliers != { }) (lib.mkMerge [
    {
      programs.ssh = {
        enable = true;
        # Strategy A produces per-repo settings entries; Strategy B produces
        # one per-atelier entry. Namespaces don't collide (A uses
        # `<host>-<atelier>-<repo>`, B uses `git-<atelier>`), so a plain merge
        # via `//` is safe. `settings` is HM ≥25.05 (replaces deprecated
        # `matchBlocks`).
        settings = renderedMatchBlocks // renderedUserKeyMatchBlocks;
      };

      programs.git = lib.mkIf (
        let aa = lib.attrValues enabledAteliers; in
          lib.any (a: a.rewriteUrls && a.credentials.deployKeys != { }) aa
          || lib.any (a: a.rewriteUrls && a.credentials.userKey != null) aa
          || enabledIdentityAteliers != { }
      ) {
        enable = lib.mkDefault true;
        # Same merge story as ssh.settings: Strategy A rewrites are repo-specific
        # (`OWNER/REPO`), Strategy B is owner-prefix (`OWNER/`). Git's "longest
        # insteadOf wins" rule means A takes precedence over B when both apply
        # to the same URL — desired behaviour (narrowest scope wins).
        # NB: `settings.url` is the HM ≥25.05 name (renamed from `extraConfig.url`,
        # INSPR-172 deprecation cleanup, 2026-05-13).
        settings.url = renderedUrlRewrites // renderedUserKeyUrlRewrites;
        includes = renderedIdentityIncludes;
      };

      home.file = renderedKnownHosts // renderedIdentityFragments;

      warnings = knownHostsWarnings;
    }

    # ── HM ≥25.05 enableDefaultConfig deprecation handling (INSPR-172) ─────
    # Newer HM versions warn at activation if `programs.ssh.enable=true` and
    # `programs.ssh.enableDefaultConfig` is left at its default of `true`.
    # We set it to false (opt-out of the legacy auto-inject) and re-declare
    # the previously-injected defaults under `settings."*"` via mkDefault
    # so consumer flakes keep their historical behaviour but can override.
    # Guarded so older HM (no `enableDefaultConfig` option) still evaluates
    # cleanly.
    (lib.mkIf hasEnableDefaultConfig {
      programs.ssh.enableDefaultConfig = lib.mkDefault false;
      programs.ssh.settings."*" = {
        forwardAgent = lib.mkDefault false;
        addKeysToAgent = lib.mkDefault "no";
        compression = lib.mkDefault false;
        serverAliveInterval = lib.mkDefault 0;
        serverAliveCountMax = lib.mkDefault 3;
        hashKnownHosts = lib.mkDefault false;
        userKnownHostsFile = lib.mkDefault "~/.ssh/known_hosts";
        controlMaster = lib.mkDefault "no";
        controlPath = lib.mkDefault "~/.ssh/master-%r@%n:%p";
        controlPersist = lib.mkDefault "no";
      };
    })
  ]);
}
