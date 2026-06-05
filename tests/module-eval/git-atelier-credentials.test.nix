# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/git-atelier-credentials.test.nix
#
# Module-eval tests for `inspr.git.atelier`. Verifies:
#   - disabled (empty cfg) module produces no programs.ssh / programs.git config
#   - enabled with one atelier + one deployKey renders an SSH match block AND
#     a url.insteadOf rewrite
#   - missing-credentials atelier throws (clear error pointing at strategies)
#   - Strategy B (userKey) throws "not implemented" at eval time
#   - Strategy C (token) throws "not implemented" at eval time
#   - Unrecognized forge.kind throws
#   - Multiple ateliers per host materialize independently (per-atelier SSH
#     alias namespace, per-atelier known_hosts file)
#   - manageKnownHosts=true with a built-in forge (github.com) renders a
#     non-empty known_hosts file
#   - manageKnownHosts=true with an unknown forge + no extraKnownHosts
#     emits a warning
# ─────────────────────────────────────────────────────────────────────────
{ harness, lib }:

let
  inherit (harness) evalModule runTests;

  gitAtelier = ../../modules/home-manager/git-atelier-credentials.nix;

  # Reference deploy key — same shape consumers will use.
  refDeployKey = {
    privateKeyPath = "/run/agenix/test-bp-bpnixcfg-deploy-key";
    pubKey = "ssh-ed25519 AAAAFakeKeyForTesting test@test 2026-05-12";
  };

  refAtelier = {
    enable = true;
    forge = {
      kind = "github";
      url = "https://github.com";
      owner = "BYTEPOETS";
    };
    credentials.deployKeys.bpnixcfg = refDeployKey;
  };

  tests = [
    # ── Disabled-module shape ────────────────────────────────────────────
    {
      name = "empty cfg produces no programs.ssh / programs.git / home.file";
      assertion =
        let r = evalModule { module = gitAtelier; config = { }; };
        in r.success
           && (r.config.programs.ssh or { }) == { }
           && (r.config.programs.git or { }) == { }
           && (r.config.home.file or { }) == { };
    }

    # ── Atelier disabled (enable=false) is a no-op ───────────────────────
    {
      name = "atelier with enable=false produces no SSH match blocks";
      assertion =
        let r = evalModule {
          module = gitAtelier;
          config = {
            inspr.git.atelier.test = refAtelier // { enable = false; };
          };
        };
        in r.success
           && (r.config.programs.ssh.settings or { }) == { };
    }

    # ── Enabled atelier + deployKey → SSH match block + url rewrite ──────
    {
      name = "enabled atelier with deployKey renders SSH matchBlock + url.insteadOf";
      assertion =
        let r = evalModule {
          module = gitAtelier;
          config = {
            inspr.git.atelier.bytepoets = refAtelier;
          };
        };
        in r.success
           && r.config.programs.ssh.enable == true
           && (r.config.programs.ssh.settings ? "github.com-bytepoets-bpnixcfg")
           && r.config.programs.ssh.settings."github.com-bytepoets-bpnixcfg".hostname == "github.com"
           && r.config.programs.ssh.settings."github.com-bytepoets-bpnixcfg".identityFile
                == "/run/agenix/test-bp-bpnixcfg-deploy-key"
           && r.config.programs.ssh.settings."github.com-bytepoets-bpnixcfg".identitiesOnly == true
           && (r.config.programs.git.settings.url
                 ? "git@github.com-bytepoets-bpnixcfg:BYTEPOETS/bpnixcfg");
    }

    # ── Atelier with no credentials at all → eval throws ─────────────────
    {
      name = "atelier with no credentials throws (clear error message)";
      assertion =
        let r = evalModule {
          module = gitAtelier;
          config = {
            inspr.git.atelier.empty = {
              enable = true;
              forge = { kind = "github"; url = "https://github.com"; owner = "anyone"; };
              # no credentials.deployKeys, no userKey, no token
            };
          };
        };
        in !r.success;
    }

    # ── Strategy B (userKey) → renders git-<atelier> SSH alias + owner-prefix URL rewrite
    {
      name = "Strategy B userKey renders git-<atelier> matchBlock + owner-prefix url.insteadOf";
      assertion =
        let r = evalModule {
          module = gitAtelier;
          config = {
            inspr.git.atelier.personal = {
              enable = true;
              forge = { kind = "github"; url = "https://github.com"; owner = "markus-barta"; };
              credentials.userKey = {
                privateKeyPath = "/run/agenix/m5-personal-userkey";
                pubKey = "ssh-ed25519 AAAAFakePersonal m5-personal@markus-barta";
              };
            };
          };
        };
        in r.success
           && (r.config.programs.ssh.settings ? "git-personal")
           && r.config.programs.ssh.settings."git-personal".hostname == "github.com"
           && r.config.programs.ssh.settings."git-personal".identityFile
                == "/run/agenix/m5-personal-userkey"
           && r.config.programs.ssh.settings."git-personal".identitiesOnly == true
           && (r.config.programs.git.settings.url ? "git@git-personal:markus-barta/")
           && r.config.programs.git.settings.url."git@git-personal:markus-barta/".insteadOf
                == [
                     "https://github.com/markus-barta/"
                     "git@github.com:markus-barta/"
                   ];
    }

    # ── Strategy B extraOwners → owner-prefix rewrite + identity include per owner
    {
      name = "extraOwners renders userKey url rewrites + identity includes for every owner";
      assertion =
        let r = evalModule {
          module = gitAtelier;
          config = {
            inspr.git.atelier.bytepoets = {
              enable = true;
              forge = {
                kind = "github";
                url = "https://github.com";
                owner = "BYTEPOETS";
                extraOwners = [ "bytepoets-mba" ];
              };
              credentials.userKey = {
                privateKeyPath = "/run/agenix/m5-bytepoets-userkey";
                pubKey = "ssh-ed25519 AAAAFakeUser m5-bytepoets@bytepoets-mba";
              };
              git = {
                userName = "bytepoets-mba";
                userEmail = "mba@bytepoets.com";
                # workspacePath omitted → hasconfig per-owner includeIf
              };
            };
          };
        };
        in r.success
           # owner-prefix url rewrite for BOTH the primary owner and the extra owner
           && (r.config.programs.git.settings.url ? "git@git-bytepoets:BYTEPOETS/")
           && (r.config.programs.git.settings.url ? "git@git-bytepoets:bytepoets-mba/")
           && r.config.programs.git.settings.url."git@git-bytepoets:bytepoets-mba/".insteadOf
                == [
                     "https://github.com/bytepoets-mba/"
                     "git@github.com:bytepoets-mba/"
                   ]
           # author-identity includeIf rendered for the extra owner too
           && lib.any (i:
                lib.hasInfix "hasconfig:remote.*.url:" i.condition
                && lib.hasInfix "bytepoets-mba" i.condition
              ) r.config.programs.git.includes;
    }

    # ── Strategy B + Strategy A coexist (independent SSH alias namespaces) ─
    {
      name = "Strategy A + B coexist: per-repo alias and per-atelier alias both render";
      assertion =
        let r = evalModule {
          module = gitAtelier;
          config = {
            inspr.git.atelier.bytepoets = {
              enable = true;
              forge = { kind = "github"; url = "https://github.com"; owner = "BYTEPOETS"; };
              # Strategy A: per-repo deploy key
              credentials.deployKeys.bpnixcfg = refDeployKey;
              # Strategy B: userKey for everything else under BYTEPOETS
              credentials.userKey = {
                privateKeyPath = "/run/agenix/m5-bytepoets-userkey";
                pubKey = "ssh-ed25519 AAAAFakeUser m5-bytepoets@bytepoets-mba";
              };
            };
          };
        };
        in r.success
           # Strategy A alias (per-repo, narrow)
           && (r.config.programs.ssh.settings ? "github.com-bytepoets-bpnixcfg")
           # Strategy B alias (per-atelier, owner-glob)
           && (r.config.programs.ssh.settings ? "git-bytepoets")
           # Both URL rewrites present
           && (r.config.programs.git.settings.url ? "git@github.com-bytepoets-bpnixcfg:BYTEPOETS/bpnixcfg")
           && (r.config.programs.git.settings.url ? "git@git-bytepoets:BYTEPOETS/");
    }

    # ── Per-atelier author identity (workspacePath form, gitdir-scoped) ────
    {
      name = "git.userName/userEmail + workspacePath renders identity fragment + gitdir includeIf";
      assertion =
        let r = evalModule {
          module = gitAtelier;
          config = {
            inspr.git.atelier.bytepoets = refAtelier // {
              git = {
                userName = "bytepoets-mba";
                userEmail = "mba@bytepoets.com";
                workspacePath = "~/Code/BYTEPOETS";
              };
            };
          };
        };
        in r.success
           # fragment file rendered
           && (r.config.home.file ? ".config/git/inspr-atelier-bytepoets.gitconfig")
           && lib.hasInfix "name = bytepoets-mba"
                r.config.home.file.".config/git/inspr-atelier-bytepoets.gitconfig".text
           && lib.hasInfix "email = mba@bytepoets.com"
                r.config.home.file.".config/git/inspr-atelier-bytepoets.gitconfig".text
           # gitdir-based includeIf wired
           && lib.any (i:
                i.condition == "gitdir:~/Code/BYTEPOETS/"
                && i.path == "~/.config/git/inspr-atelier-bytepoets.gitconfig"
              ) r.config.programs.git.includes;
    }

    # ── Per-atelier author identity (no workspacePath → hasconfig fallback)
    {
      name = "git.userName/userEmail without workspacePath uses hasconfig remote-URL match";
      assertion =
        let r = evalModule {
          module = gitAtelier;
          config = {
            inspr.git.atelier.personal = {
              enable = true;
              forge = { kind = "github"; url = "https://github.com"; owner = "markus-barta"; };
              credentials.userKey = {
                privateKeyPath = "/run/agenix/m5-personal-userkey";
                pubKey = "ssh-ed25519 AAAA…";
              };
              git = {
                userName = "Markus Barta";
                userEmail = "markus@barta.com";
                # workspacePath omitted on purpose
              };
            };
          };
        };
        in r.success
           && lib.any (i:
                lib.hasInfix "hasconfig:remote.*.url:" i.condition
                && lib.hasInfix "github.com" i.condition
                && lib.hasInfix "markus-barta" i.condition
              ) r.config.programs.git.includes;
    }

    # ── Strategy C (token) → throws "not implemented in MVP" ─────────────
    {
      name = "Strategy C (token) declaration throws not-implemented";
      assertion =
        let r = evalModule {
          module = gitAtelier;
          config = {
            inspr.git.atelier.c-test = {
              enable = true;
              forge = { kind = "github"; url = "https://github.com"; owner = "x"; };
              credentials.token = {
                tokenPath = "/run/agenix/test-token";
                botUser = "x-access-token";
              };
            };
          };
        };
        in !r.success;
    }

    # ── Multiple ateliers materialize independently ──────────────────────
    {
      name = "two ateliers produce two SSH alias namespaces + two known_hosts files";
      assertion =
        let r = evalModule {
          module = gitAtelier;
          config = {
            inspr.git.atelier.bytepoets = refAtelier;
            inspr.git.atelier.personal = {
              enable = true;
              forge = { kind = "github"; url = "https://github.com"; owner = "markus-barta"; };
              credentials.deployKeys.nixcfg = refDeployKey // {
                privateKeyPath = "/run/agenix/test-personal-nixcfg-deploy";
              };
            };
          };
        };
        in r.success
           && (r.config.programs.ssh.settings ? "github.com-bytepoets-bpnixcfg")
           && (r.config.programs.ssh.settings ? "github.com-personal-nixcfg")
           && (r.config.home.file ? ".ssh/known_hosts.d/inspr-git-atelier-bytepoets")
           && (r.config.home.file ? ".ssh/known_hosts.d/inspr-git-atelier-personal");
    }

    # ── known_hosts for github.com is non-empty (built-in keys load) ─────
    {
      name = "manageKnownHosts=true on github.com renders non-empty known_hosts file";
      assertion =
        let r = evalModule {
          module = gitAtelier;
          config = {
            inspr.git.atelier.bytepoets = refAtelier;
          };
        };
        in r.success
           && r.config.home.file.".ssh/known_hosts.d/inspr-git-atelier-bytepoets".text != ""
           && lib.hasInfix "github.com ssh-ed25519"
                r.config.home.file.".ssh/known_hosts.d/inspr-git-atelier-bytepoets".text;
    }

    # ── Unknown forge + no extras + manageKnownHosts=true → warning ─────
    {
      name = "manageKnownHosts=true on unknown forge without extras emits a warning";
      assertion =
        let r = evalModule {
          module = gitAtelier;
          config = {
            inspr.git.atelier.diy = {
              enable = true;
              forge = { kind = "ssh"; url = "https://git.example.invalid"; owner = "me"; };
              credentials.deployKeys.foo = refDeployKey;
              # manageKnownHosts defaults to true; no extraKnownHosts; no built-in keys
            };
          };
        };
        in r.success
           && lib.any (w: lib.hasInfix "manageKnownHosts" w) r.config.warnings;
    }

    # ── manageKnownHosts=false → no known_hosts file rendered ────────────
    {
      name = "manageKnownHosts=false renders no known_hosts file";
      assertion =
        let r = evalModule {
          module = gitAtelier;
          config = {
            inspr.git.atelier.test = refAtelier // {
              manageKnownHosts = false;
            };
          };
        };
        in r.success
           && !(r.config.home.file ? ".ssh/known_hosts.d/inspr-git-atelier-test");
    }
  ];

in
  runTests "git-atelier-credentials" tests
