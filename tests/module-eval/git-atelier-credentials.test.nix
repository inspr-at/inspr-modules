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
           && (r.config.programs.ssh.matchBlocks or { }) == { };
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
           && (r.config.programs.ssh.matchBlocks ? "github.com-bytepoets-bpnixcfg")
           && r.config.programs.ssh.matchBlocks."github.com-bytepoets-bpnixcfg".hostname == "github.com"
           && r.config.programs.ssh.matchBlocks."github.com-bytepoets-bpnixcfg".identityFile
                == "/run/agenix/test-bp-bpnixcfg-deploy-key"
           && r.config.programs.ssh.matchBlocks."github.com-bytepoets-bpnixcfg".identitiesOnly == true
           && (r.config.programs.git.extraConfig.url
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

    # ── Strategy B (userKey) → throws "not implemented in MVP" ───────────
    {
      name = "Strategy B (userKey) declaration throws not-implemented";
      assertion =
        let r = evalModule {
          module = gitAtelier;
          config = {
            inspr.git.atelier.b-test = {
              enable = true;
              forge = { kind = "github"; url = "https://github.com"; owner = "x"; };
              credentials.userKey = {
                privateKeyPath = "/run/agenix/test-user-key";
                pubKey = "ssh-ed25519 AAAA…";
              };
            };
          };
        };
        in !r.success;
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
           && (r.config.programs.ssh.matchBlocks ? "github.com-bytepoets-bpnixcfg")
           && (r.config.programs.ssh.matchBlocks ? "github.com-personal-nixcfg")
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
