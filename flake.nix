# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                  inspr-modules — public library flake                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Reusable Home Manager modules + utilities from the INSPR initiative.
# Mission: "where your inspirations live" — democratize software dev by
# letting anyone consume the same primitives Markus uses on his own fleet.
#
# Atelier-pattern graduation: this is the shared atelier — the public
# library that "studios" (context flakes: Markus's nixcfg, family
# flake, family flake, future paid-product flakes) consume. Each studio
# provides only its identity-specific values; the rest comes from the
# atelier for free. See README.md "atelier pattern" for the full metaphor.
# (Older docs called this "Pattern β" — same architecture, opaque name.)
#
# Exports:
#   homeManagerModules.agent-secrets   Materialize agenix-encrypted env files
#                                       to a per-user "agent-exception" dir.
#   homeManagerModules.agent-skills    Declarative agent-skill provisioning
#                                       across CLI harnesses (Claude Code,
#                                       Codex, extensible). Bundled skills
#                                       ship under skills/<name>/.
#   homeManagerModules.git-atelier-credentials
#                                       Per-atelier outbound git credentials
#                                       (Strategy A deploy keys; B/C option-
#                                       typed). Forge-agnostic: github,
#                                       forgejo, codeberg, gitlab, gitea,
#                                       sourcehut, bare-SSH.
#   homeManagerModules.git-identity    Multi-identity git config with
#                                       gitdir + hasconfig:remote.*.url
#                                       includeIf rules.
#   homeManagerModules.paimos-config   Materialize Paimos instance routing
#                                       without credentials. Auth stays in the OS
#                                       keyring or process runtime environment.
#   homeManagerModules.ssh-authorized  Declarative ~/.ssh/authorized_keys
#                                       via aliased key map + trust list,
#                                       with marker-block coexistence.
#   homeManagerModules.default         Aggregate of all HM modules above.
#   nixosModules.ssh-authorized        System-side counterpart to the HM
#                                       ssh-authorized — manages
#                                       users.users.<u>.openssh.authorizedKeys.keys
#                                       from the same keyring (multi-user,
#                                       status-filtered, force-toggleable).
#   nixosModules.routing-edge          Prefix-preserving Traefik file-provider
#                                       edge (disabled by default; managed or
#                                       external-file-provider fragment mode).
#   nixosModules.aithema-workspace      Aithema runtime service with protected
#                                       operator config and durable state.
#   nixosModules.default               Aggregate of all NixOS modules.
#   packages.<system>.secrets-audit    Bash script: detect drift between
#                                       secrets/*.age and secrets.nix
#                                       declarations.
#   packages.<system>.inspr            Bash CLI: INSPR onboarding diagnostic +
#                                       heal + onboard + readiness sub-commands.
#                                       Replaces the older inspr-doctor.sh probe.
#   packages.<system>.routing-edge     Traefik file-provider compiler built from
#                                       this flake (`insprSource = self`).
#   packages.<system>.aithema-workspace Immutable public Aithema 0.6.0 runtime
#                                       with lock-integrity-pinned dependencies.
#
# Consumer pattern (in your flake.nix):
#   inputs.inspr-modules.url = "github:inspr-at/inspr-modules/v0.10.0";  # pin a tag; main moves
#   inputs.inspr-modules.inputs.nixpkgs.follows = "nixpkgs";
#
#   home.imports = [
#     inputs.inspr-modules.homeManagerModules.git-identity
#     # ... or .default for all
#   ];
#
# SPDX-License-Identifier: AGPL-3.0-only
# See LICENSE for the complete terms and the network-source obligation.
#
{
  description = "INSPR atelier — reusable Home Manager + NixOS modules and utilities (the public, shared mechanics layer)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    {
      # ── Home Manager modules ───────────────────────────────────────────
      # Each module is import-once; consumers add to their `imports = [ ... ]`
      # and configure via the `inspr.<name>.*` option namespace.
      homeManagerModules = {
        agent-secrets = ./modules/home-manager/agent-secrets.nix;
        agent-skills = ./modules/home-manager/agent-skills.nix;
        inspr-cli = ./modules/home-manager/inspr-cli.nix;
        devenv-direnv-fix = ./modules/home-manager/devenv-direnv-fix.nix;
        git-atelier-credentials = ./modules/home-manager/git-atelier-credentials.nix;
        git-identity = ./modules/home-manager/git-identity.nix;
        paimos-config = ./modules/home-manager/paimos-config.nix;
        ssh-authorized = ./modules/home-manager/ssh-authorized.nix;
        default = ./modules/home-manager/default.nix;
      };

      # ── NixOS modules ──────────────────────────────────────────────────
      # System-side modules — same `inspr.<name>.*` option namespace as
      # the HM modules where applicable, but render into NixOS-native
      # option spots (e.g. `users.users.<u>.openssh.authorizedKeys.keys`).
      # Consumers import at NixOS-module scope (top-level
      # configuration.nix or shared profile).
      # ── Doctrine data ──────────────────────────────────────────────────
      # Calendar v2 display weights as data (INSPR-400). `data` is the parsed
      # JSON, `source` the path consumers copy or read at build time. The
      # rendered CSS lives in packages.<system>.calendar-version-display-css.
      # `data.design_revision` names the authoritative display design revision
      # (3 since INSPR-414). Consumers pin bytes, so a new revision here only
      # reaches a consumer when that consumer upgrades its own pin.
      lib = {
        calendarVersionDisplay = {
          source = ./lib/calendar-version-display.json;
          data = builtins.fromJSON (builtins.readFile ./lib/calendar-version-display.json);
        };
      };

      nixosModules = {
        ssh-authorized = ./modules/nixos/ssh-authorized.nix;
        routing-edge = ./packages/routing-edge/nix/module.nix;
        aithema-workspace = ./modules/nixos/aithema-workspace.nix;
        default = ./modules/nixos/default.nix;
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        # ── CLI scripts as packages ──────────────────────────────────────
        packages = {
          secrets-audit = pkgs.callPackage ./pkgs/secrets-audit { };
          inspr = pkgs.callPackage ./pkgs/inspr { };
          routing-edge = pkgs.callPackage ./packages/routing-edge/nix { insprSource = self; };
          aithema-workspace = pkgs.callPackage ./packages/aithema-workspace { };
          calendar-version-display-css =
            pkgs.runCommand "calendar-version-display.css" { nativeBuildInputs = [ pkgs.python3 ]; } ''
              python3 ${./scripts/render-calendar-version-display.py} ${./lib/calendar-version-display.json} > $out
            '';
        };

        # ── Test suite (run via `nix flake check`) ───────────────────────
        # Each check is a derivation that succeeds (touches $out) if its
        # test passes, fails the build otherwise. Sandbox-friendly — no
        # network, all deps via nativeBuildInputs.
        checks =
          let
            secretsAuditPkg = pkgs.callPackage ./pkgs/secrets-audit { };
            workerDoctrineBundle = import ./lib/worker-doctrine-bundle.nix {
              inherit pkgs;
              skillSource = ./skills/inspr-worker-doctrine/SKILL.md;
              attributionSource = ./AGENTS.md;
              versioningSource = ./docs/AGENTS-VERSIONING.md;
              displaySource = ./lib/calendar-version-display.json;
            };

            # Module-eval suite results (INSPR-267). Evaluation is lazy —
            # nothing forces until the module-eval check derivation is
            # instantiated — and the suite never throws, so `nix flake
            # show` and check enumeration always work; a red unit test
            # fails as an ordinary check build below. Deliberately NOT
            # deduplicated across systems: per-system eval can genuinely
            # differ (e.g. the darwin-only stdenv recursion documented in
            # devenv-direnv-fix.test.nix), and deduping would mask
            # system-specific eval regressions.
            moduleEvalResults = import ./tests/module-eval {
              inherit pkgs;
              inherit (pkgs) lib;
              # The suite imports EVERY exported module through the harness.
              # Driven by the real export attrsets, not a hand-kept list —
              # a hand-kept list is how "default imports all seven" drifted.
              inherit (self) homeManagerModules nixosModules;
            };

            routingEdgeChecks = import ./packages/routing-edge/nix/tests {
              inherit pkgs;
              insprSource = self;
            };

            aithemaWorkspacePkg = pkgs.callPackage ./packages/aithema-workspace { };
          in
          {
            # The bundled design-frontier skill accepts five independently
            # attributed concepts and emits one deterministic, local-only
            # comparison gallery. Exercise both the happy path and its
            # fail-closed manifest/path/ownership boundaries in CI, including
            # UUIDv7, hostile text, symlink escapes, and output clobbering.
            design-frontier-gallery = pkgs.runCommand "design-frontier-gallery"
              {
                nativeBuildInputs = [ pkgs.python3 ];
              }
              ''
                cp -R ${./skills/design-frontier-gauntlet/scripts} ./scripts
                python3 ./scripts/test_build_gallery.py
                touch $out
              '';

            # Repository licensing is part of the build contract: canonical
            # legal text, package metadata, source headers and public doctrine
            # must stay aligned on the exact SPDX identifier.
            license-surface = pkgs.runCommand "license-surface"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gnugrep
                ];
              }
              ''
                bash ${./tests/license-surface.sh} ${self}
                touch $out
              '';

            # Current repository and container references are operational
            # inputs. Keep them on the canonical INSPR organization while
            # preserving the intentionally personal nixcfg location.
            repository-location-surface = pkgs.runCommand "repository-location-surface"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gnugrep
                ];
              }
              ''
                bash ${./tests/repository-location-surface.sh} ${self}
                touch $out
              '';

            # Consumer CI can enforce the same-upstream doctrine pin invariant
            # without running the full repository audit. The fixture suite
            # proves index-only gitlink discovery, staged-pin authority,
            # per-upstream equality, focused assertion boundaries, fail-closed
            # argument parsing, and macOS Bash 3.2-compatible syntax (INSPR-323).
            doctrine-check-multipath = pkgs.runCommand "doctrine-check-multipath"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gawk
                  pkgs.git
                  pkgs.gnugrep
                  pkgs.gnused
                  pkgs.python3
                ];
              }
              ''
                DOCTRINE_TEST_BASH=${pkgs.bash}/bin/bash \
                  bash ${./tests/doctrine-check-multipath.sh} ${self}
                touch $out
              '';

            # The estate versioning policy is normative and linked from the
            # doctrine index. Keep its v2 calendar grammar, real-date validation,
            # normalized ordering, gradual transition contract, and README
            # boundary executable (INSPR-320).
            calendar-version-doctrine = pkgs.runCommand "calendar-version-doctrine"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gnugrep
                  pkgs.python3
                ];
              }
              ''
                bash ${./tests/calendar-version-doctrine.sh} ${self}
                touch $out
              '';

            # The display weights are data (INSPR-400): the JSON validates, the
            # doctrine's CSS block and prose numbers equal the rendered data,
            # and the flake package renders the same bytes.
            calendar-version-display = pkgs.runCommand "calendar-version-display"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gawk
                  pkgs.git
                  pkgs.gnugrep
                  pkgs.python3
                ];
              }
              ''
                bash ${./tests/calendar-version-display.sh} ${self}
                touch $out
              '';

            # Home Manager installs a harness-readable worker-doctrine bundle
            # whose references are byte-identical to the canonical attribution
            # mirror and calendar-version policy (INSPR-322). Exercise both the
            # positive bundle and deliberate mirror drift.
            worker-doctrine-surface = pkgs.runCommand "worker-doctrine-surface"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gnugrep
                ];
              }
              ''
                bash ${./tests/worker-doctrine-surface.sh} ${self} ${workerDoctrineBundle}

                cp -R ${workerDoctrineBundle} ./drifted
                chmod -R u+w ./drifted
                printf '\nfixture drift\n' >> ./drifted/references/AGENTS.md
                if bash ${./tests/worker-doctrine-surface.sh} ${self} ./drifted; then
                  echo "worker-doctrine drift fixture unexpectedly passed" >&2
                  exit 1
                fi

                touch $out
              '';

            # Functional tests for the secrets-audit binary. Runs each
            # fixture (clean / declared-missing / orphan / with-comments)
            # through the binary and asserts exit codes + output content.
            # Includes a regression test for INSPR-50 (--help PATH leak).
            secrets-audit-functional = pkgs.runCommand "secrets-audit-functional"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gnugrep
                  pkgs.gnused
                  secretsAuditPkg
                ];
              }
              ''
                # Copy the tests dir into the sandbox (sources are read-only by default)
                cp -r ${./tests} ./tests
                chmod -R u+w ./tests
                cd ./tests/secrets-audit
                SECRETS_AUDIT=${secretsAuditPkg}/bin/secrets-audit \
                  bash ./run-tests.sh
                touch $out
              '';

            # Executes rendered paimos-config activations against synthetic
            # files. Covers fail-before-replace behavior, the legacy api_key
            # rollout guard, shell-safe diagnostics, and CR/LF/quote-safe URL
            # encoding without reading any real user configuration.
            paimos-config-functional = import ./tests/paimos-config-functional.nix {
              inherit pkgs;
            };

            # Sources the rendered fleet.conf with Bash, matching the CLI's
            # execution path. Shell-active values must survive literally and
            # null/empty configuration must remain assignment-free.
            inspr-cli-functional = import ./tests/inspr-cli-functional.nix {
              inherit pkgs;
            };

            # Read-only development-machine readiness contract and CLI
            # (INSPR-377). Deterministic fixtures only; does not claim live
            # customer acceptance or Paimos launch gating. Runs on Darwin
            # without building NixOS.
            inspr-readiness =
              let
                insprPkg = pkgs.callPackage ./pkgs/inspr { };
              in
              pkgs.runCommand "inspr-readiness"
                {
                  nativeBuildInputs = [
                    pkgs.python3
                    pkgs.bash
                    pkgs.coreutils
                    pkgs.git
                    pkgs.gnugrep
                  ];
                }
                ''
                  export PYTHONPATH=${./pkgs/inspr}
                  export INSPR=${insprPkg}/bin/inspr
                  export GIT_AUTHOR_NAME=ReadinessFixture
                  export GIT_AUTHOR_EMAIL=dev@example.invalid
                  export GIT_COMMITTER_NAME=ReadinessFixture
                  export GIT_COMMITTER_EMAIL=dev@example.invalid
                  python3 -m unittest discover -s ${./tests/inspr-readiness} -p 'test_*.py' -v
                  touch $out
                '';

            # Kernel-mirror freshness gate (INSPR-278). Editing the kernel
            # without re-mirroring AGENTS.md burned us in INSPR-269 (the 🔴
            # trust-contexts rule was invisible to non-Claude harnesses for
            # over a week). The mirror block carries a KERNEL-MIRROR-OF
            # sha256 attestation the re-mirror step must update; this check
            # recomputes the kernel hash and fails on mismatch — drift dies
            # at commit time, before it distributes to any consumer.
            kernel-mirror-stamp =
              pkgs.runCommand "kernel-mirror-stamp"
                {
                  nativeBuildInputs = [
                    pkgs.coreutils
                    pkgs.gnugrep
                    pkgs.gnused
                  ];
                }
                ''
                  kernel_hash="$(sha256sum ${./docs/AGENTS-KERNEL.md} | cut -d' ' -f1)"
                  stamp="$(grep -o 'KERNEL-MIRROR-OF: sha256:[0-9a-f]*' ${./AGENTS.md} | sed 's/.*sha256://')"
                  if [ -z "$stamp" ]; then
                    echo "AGENTS.md lacks the KERNEL-MIRROR-OF stamp" >&2
                    exit 1
                  fi
                  if [ "$stamp" != "$kernel_hash" ]; then
                    echo "kernel-mirror drift: docs/AGENTS-KERNEL.md sha256 ($kernel_hash) != AGENTS.md stamp ($stamp)." >&2
                    echo "Re-mirror the irreducible subset into AGENTS.md, then update the stamp (sha256sum docs/AGENTS-KERNEL.md)." >&2
                    exit 1
                  fi
                  touch $out
                '';

            # Ticket-first work attribution is an always-on global protocol
            # (INSPR-321), not an optional product-gauntlet convention. Keep
            # the kernel, non-Claude mirror, full reference and dispatcher in
            # lockstep and reject the retired opt-in wording.
            work-attribution-doctrine = pkgs.runCommand "work-attribution-doctrine"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.gnugrep
                ];
              }
              ''
                bash ${./tests/work-attribution-doctrine.sh} ${self}
                touch $out
              '';

            # inspr --help must tell the truth (INSPR-258): every dispatch
            # command appears and no stale NOT-YET-IMPLEMENTED claims remain.
            inspr-help-surface =
              let
                insprPkg = pkgs.callPackage ./pkgs/inspr { };
              in
              pkgs.runCommand "inspr-help-surface"
                { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
                  help="$(${insprPkg}/bin/inspr --help)"
                  for cmd in check heal onboard post-deploy readiness; do
                    printf '%s' "$help" | grep -q "$cmd" || {
                      echo "inspr --help no longer mentions '$cmd'" >&2
                      exit 1
                    }
                  done
                  if printf '%s' "$help" | grep -qi "NOT YET IMPLEMENTED"; then
                    echo "stale NOT-YET-IMPLEMENTED claim in inspr --help" >&2
                    exit 1
                  fi
                  touch $out
                '';

            # Executes the rendered ssh-authorized activation against
            # synthetic authorized_keys files (INSPR-261): fresh host,
            # valid-marker replacement preserving manual lines, missing
            # end marker fails loudly with the original untouched, and
            # substring-only markers never truncate.
            ssh-authorized-functional = import ./tests/ssh-authorized-functional.nix {
              inherit pkgs;
            };

            # Closed Git-blob import boundary for routing-edge (INSPR-390).
            routing-edge-import-boundary = pkgs.runCommand "routing-edge-import-boundary"
              {
                nativeBuildInputs = [ pkgs.python3 pkgs.git ];
              }
              ''
                cd ${self}
                python3 -m unittest discover -s tests -p 'test_routing_edge_import_boundary.py' -v
                touch $out
              '';

            routing-edge-import-surface = pkgs.runCommand "routing-edge-import-surface"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gnugrep
                  pkgs.python3
                ];
              }
              ''
                bash ${./tests/routing-edge-import-surface.sh} ${self}
                touch $out
              '';

            # Python compiler + contract validator tests for routing-edge.
            routing-edge-python = pkgs.runCommand "routing-edge-python"
              {
                nativeBuildInputs = [ pkgs.python3 ];
              }
              ''
                cd ${self}/packages/routing-edge
                PYTHONPATH=. python3 -m unittest discover -s tests -p 'test_compile.py' -v
                cd ${self}/contracts/routing
                PYTHONPATH=. python3 -m unittest discover -s tests -v
                touch $out
              '';

            # Package build + installed-command proof and pure module/NixOS eval.
            routing-edge-nix-eval = pkgs.runCommand "routing-edge-nix-eval"
              { }
              ''
                cat <<'EOF' > $out
${routingEdgeChecks.report}
EOF
                if [ "${toString routingEdgeChecks.ok}" != "1" ]; then
                  echo "routing-edge nix eval failed" >&2
                  exit 1
                fi
              '';

            routing-edge-package-proof = routingEdgeChecks.packageProof;
            routing-edge-external-install-proof = routingEdgeChecks.externalInstallProof;

            # Execute the installed Aithema CLI away from its source tree:
            # help, synthetic loopback readiness under a non-root build user,
            # and the CLI's own graceful SIGTERM path. Linux service activation
            # remains a separate remote proof; this check is Darwin-safe.
            aithema-workspace-package-proof = pkgs.runCommand "aithema-workspace-package-proof"
              {
                __darwinAllowLocalNetworking = true;
                nativeBuildInputs = [
                  pkgs.coreutils
                  pkgs.gnugrep
                  pkgs.gnused
                  pkgs.nodejs_24
                ];
              }
              ''
                set -eu

                test "${aithemaWorkspacePkg.passthru.release.sourceRev}" = \
                  902adaf2eb8e707f8e93c54f1c34f8688dbb54cd
                test "${aithemaWorkspacePkg.passthru.release.runtimeSha256}" = \
                  1377489645b97e3a71dd30d46c9d193f26237eb9a14084fc593078bdefe22dec
                test "$(sha256sum ${./packages/aithema-workspace/package-lock.json} | cut -d' ' -f1)" = \
                  acd386661ff0c54ba827082a3872593bc6f50204e72eaaa0a2aeb3c487d68f02
                ${aithemaWorkspacePkg}/bin/aithema-workspace --help \
                  | grep -q 'Usage: aithema-workspace --config FILE'

                run_dir="$TMPDIR/aithema-proof"
                mkdir -p "$run_dir/state"
                cd "$run_dir"
                config_file="$run_dir/runtime-config.json"
                log_file="$run_dir/service.log"
                printf '%s\n' '{' \
                  '  "mode": "test",' \
                  '  "listenHost": "127.0.0.1",' \
                  '  "listenPort": 0,' \
                  '  "dataDir": "./state",' \
                  '  "publicBasePath": "/proof",' \
                  '  "defaultProvider": "mock",' \
                  '  "identity": {' \
                  '    "kind": "demo",' \
                  '    "defaultSubject": "proof-reviewer",' \
                  '    "memberships": [{' \
                  '      "subject": "proof-reviewer",' \
                  '      "party_ref": "party:proof-reviewer",' \
                  '      "actor_kind": "human",' \
                  '      "roles": ["requirements_approver"],' \
                  '      "projects": []' \
                  '    }]' \
                  '  },' \
                  '  "providers": { "mock": { "kind": "mock", "chunkDelayMs": 0 } }' \
                  '}' > "$config_file"
                chmod 600 "$config_file"

                ${aithemaWorkspacePkg}/bin/aithema-workspace \
                  --config "$config_file" --shutdown-grace-ms 1000 \
                  > "$log_file" 2>&1 &
                service_pid=$!

                base_url=""
                attempt=0
                while [ "$attempt" -lt 100 ]; do
                  base_url="$(sed -n 's/^Aithema workspace listening at \(http[^ ]*\)$/\1/p' "$log_file" | head -n 1)"
                  [ -n "$base_url" ] && break
                  kill -0 "$service_pid" 2>/dev/null || {
                    sed -n '1,80p' "$log_file" >&2
                    exit 1
                  }
                  attempt=$((attempt + 1))
                  sleep 0.1
                done
                [ -n "$base_url" ]

                node --input-type=module -e \
                  'const response = await fetch(process.argv[1]); const body = await response.json(); if (response.status !== 200 || body.ok !== true || body.ready !== true) process.exit(1);' \
                  "$base_url/health"

                kill -TERM "$service_pid"
                wait "$service_pid"
                grep -q 'Aithema workspace stopped cleanly.' "$log_file"
                touch $out
              '';

            # Module-eval tests (INSPR-72): exercise HM module options +
            # assertions + eval-time throws via lib.evalModules + a stub
            # HM harness. Catches regressions BEFORE `home-manager switch`
            # — assertions firing at the right times, REQUIRED options
            # staying required, deprecated options still warning, etc.
            #
            # The eval happens when this derivation is instantiated; the
            # pass/fail decision happens when it is BUILT (INSPR-267):
            # report always lands in the build log, $out persists it on
            # success, and any failed sub-test exits non-zero — an
            # ordinary failed check, not a flake-eval error.
          }
          # ── NixOS VM integration test (Linux only) ───────────────────────
          # Boots a server + client and proves sshd ADMITS trusted keys and
          # REJECTS untrusted/revoked ones. Needs a KVM builder with the
          # `nixos-test` system feature. On macOS the attribute does not
          # exist, so `nix flake check` there is unaffected. See
          # tests/nixos-vm/ssh-authorized.nix for what it proves and why.
          // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
            nixos-vm-ssh-authorized = import ./tests/nixos-vm/ssh-authorized.nix {
              inherit pkgs;
              sshAuthorizedModule = ./modules/nixos/ssh-authorized.nix;
            };
          }
          // {
            module-eval = pkgs.runCommand "module-eval-tests"
              {
                report = moduleEvalResults.report;
                failedCount = toString (builtins.length moduleEvalResults.failedTests);
                passAsFile = [ "report" ];
              } ''
                cat "$reportPath"
                cp "$reportPath" $out
                if [ "$failedCount" != "0" ]; then
                  echo "module-eval: $failedCount sub-test(s) failed" >&2
                  exit 1
                fi
              '';
          };
      }
    );
}
