# Changelog

All notable changes to **inspr-modules** are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.4.0] - 2026-08-18

First release whose documentation describes the release. Everything below
already existed on `main`; the problem was that `v0.3.7` — the tag the README
told consumers to pin — shipped none of it. An independent reviewer stopped at
exactly that point.

### Added

- `scripts/leak-guard.sh` — refuses operator-identifying content on the public
  surface. Whole-repo scope, fails closed outside a git repository or on an
  unreadable file, and never echoes matched text (a detector that prints what
  it found reproduces the leak into CI logs). Reasoned allowlist in
  `.leak-guard-allow`.
- `scripts/doctrine-check.sh` — five assertions that a consuming repository's
  doctrine wiring actually resolves. Every failure it catches is silent at
  runtime: a dangling `@`-ref loads nothing and reports nothing.
- `SECURITY.md` — private vulnerability reporting, response targets, and an
  explicit invitation to report ways of defeating either guard.
- `CONTRIBUTING.md` and `CODEOWNERS` — the repository previously had detailed
  rules for the maintainer's own agents and none for a human stranger.
- `homeManagerModules.inspr-cli` — renders `fleet.conf` from typed options.
  Deliberately **not** in the `default` aggregate: it writes a config file, so
  it is opt-in.
- A test that compiles the NixOS module's documented example, so an example
  that does not evaluate now fails CI.
- `checks.<linux>.nixos-vm-ssh-authorized` — a real NixOS VM test for the SSH
  admission module: boots server + client, proves the trusted key logs in and
  untrusted / revoked / cross-user keys are refused, and that `force = true`
  renders exactly the trusted list. Verified red-then-green: a runtime-only
  bug (every user silently receiving another user's keys) passes every
  eval-time assertion and is caught only here.

### Fixed

- **`nixosModules.ssh-authorized`'s documented example did not evaluate.** It
  trusted an SSH key alias the example never declared, so the module's own
  guard threw. On an admission-control module.
- The `inspr` CLI carried the maintainer's tailnet endpoint and identity as
  built-in defaults; the git-identity check asserted one specific person's
  email as its pass condition, so it reported *pass* for the maintainer and was
  meaningless for everyone else. Now configurable, and skips when unset.
- The package failed to build — ShellCheck rejected quoting introduced during
  that parameterisation.
- Public documentation linked into two private repositories (guaranteed 404s
  and disclosure of private paths), described the library as one person's fleet
  config, and documented options using that person's hostnames.
- README claimed the wrong version, the wrong test count, the wrong number of
  doctrine-check assertions, and that the `default` aggregate imported every
  module.

### Changed

- `SECURITY.md` no longer claims the repository is "identity-free". The
  defensible claim is narrower and now stated: no live credentials, no private
  endpoints.
- Module examples use generic names (`alice@laptop`) rather than the
  maintainer's machines — one of which was decommissioned.

### Known limitations

- Both guard scripts are incomplete. They walk the filesystem where they should
  read the git index, and three audit rounds each found a new false negative of
  that shape. They catch what they catch; do not treat a green result as proof.
- Only `ssh-authorized` has a NixOS VM integration test. The other modules are eval-only, against stub harnesses.
- `leak-guard.sh` matches a hard-coded pattern set. It is usable as-is only by
  this project; adopting it elsewhere means forking and rewriting `PATTERNS`.

---

## [0.4.1] - 2026-08-18

`v0.4.0` was cut so the tag would match its documentation, and then three more
pull requests landed on `main` before anyone re-tagged — a NixOS consumer
walkthrough, a VM integration test, and a security-policy correction. An
independent reviewer's top blocker was, once again, that the recommended tag
did not contain what the default-branch manual described. This release
contains everything on `main`, and is the last commit before the tag.

### Added

- `checks.<linux>.nixos-vm-ssh-authorized` — a real NixOS VM test for the SSH
  admission module: boots server + client, proves the trusted key logs in and
  untrusted / revoked / cross-user keys are refused, and that `force = true`
  renders exactly the trusted list. Runs in CI on GitHub's Linux runners.
  Verified red-then-green against a runtime-only bug that every eval-time
  assertion misses.
- README: a NixOS consumer example for `ssh-authorized` (previously findable
  only in a 300-line module header); a doctrine-check adoption recipe covering
  the submodule, the `@`-ref and the command symlinks; the guard's environment
  knobs; a plain statement that `leak-guard` is this repository's own lint and
  needs a fork to protect anyone else.

### Fixed

- `SECURITY.md` directed reporters to GitHub private vulnerability reporting,
  which was **disabled** on the repository. It is now enabled, alongside secret
  scanning and push protection, and the policy names the mechanisms without
  calling any of them a guarantee.
- The deprecation example promised removal of `identityFile` "in v0.2.0",
  contradicting the policy two lines above it (removal in the next MAJOR) and
  the shipped code (still present at 0.4.x, deliberately). The example now
  matches the policy.
- README overstated what consumer evaluation proves for `ssh-authorized`: the
  option accepts any string, so a mistyped key evaluates fine and fails only
  at login. Now stated, with the check to run first.
- An orphaned sentence fragment under the support table, and a roadmap line
  claiming the project is "currently HM-only" when it ships a NixOS module.

### Known limitations (unchanged from 0.4.0, restated so nobody has to dig)

- Both guard scripts are incomplete and read the worktree rather than the git
  index; a staged leak with an unstaged local cleanup passes `leak-guard`.
  Tracked (INSPR-300); do not treat a green result as proof.
- Only `ssh-authorized` has a VM test. Other modules are eval-only, on stubs.
- One maintainer; only the latest tag receives fixes; only `nixos-unstable`
  plus matching Home Manager is claimed.

---

## [0.4.2] - 2026-08-18

### Fixed

- **`homeManagerModules.default` did not parse in v0.4.0 or v0.4.1.** A
  comment edit left a stray `imports = [` outside the module function. The
  advertised aggregate was unimportable in two consecutive releases and no
  check noticed, because nothing imported the flake's exports through the
  framework they are exported for. An outside reviewer found it by parsing
  every `.nix` file by hand.
- The Home Manager consumer example imported `paimos-config` in a
  `git-identity` walkthrough and did not say that `./your-home.nix` must supply
  the ordinary Home Manager baseline (`home.username`, `homeDirectory`,
  `stateVersion`); a reader copying it hit a missing-option error.
- The NixOS example called itself a "Minimal `flake.nix`" but cannot build a
  system (no filesystem, bootloader or `system.stateVersion`). Relabelled as a
  module-integration example, with what it needs around it stated.

### Added

- `tests/module-eval/exports-importable.test.nix` — imports **every** module in
  the flake's real `homeManagerModules` and `nixosModules` attrsets with default
  configuration. Driven by the export attrsets themselves, so it cannot drift
  from what is advertised. Verified red: reinstating the v0.4.1 file fails the
  suite with the exact syntax error. 104 eval tests, was 92.
- The stub Home Manager harness now declares `xdg`. It did not, so
  `homeManagerModules.inspr-cli` — which sets `xdg.configFile` — could not be
  imported in tests despite working under real Home Manager. Found by the new
  export test on its first run.

### Known limitations (unchanged)

- Both guard scripts read the worktree, not the git index (INSPR-300).
- Only `ssh-authorized` has a VM test; other modules are eval-only, on stubs.
- One maintainer; latest tag only; `nixos-unstable` + matching HM only.

---

## [0.4.3] - 2026-08-18

Documentation only. Cut because the rule adopted in 0.4.1 — docs ship with the
tag that describes them — is worth more than avoiding a fourth same-day
version number. This is the last release of the day; the next one should be
boring and some weeks away.

### Changed

- Guard language matched to mechanism. `leak-guard` "refuse to publish" and
  "required and blocking" described a pre-publication barrier; what exists is a
  **post-push detector plus PR gate** that scans the working tree, not the git
  index. Now says so, next to the usage instructions rather than only here.
- One note near the top of the README explaining that `INSPR-nnn` keys point
  at a private tracker and carry nothing a consumer needs.
- README test count corrected to 104 (said 92 in the release cut to make counts
  accurate — same drift, same fix).

---

## [0.4.4] - 2026-08-18

### Fixed

- The README's Home Manager walkthrough imported only `git-identity` while its
  `home.nix` block configured `inspr.paimos-cli`; pasted together they failed
  with "The option inspr.paimos-cli does not exist". Import restored. Found by
  an outside evaluation, under a contribution rule that says every example must
  evaluate — the rule was documented more thoroughly than it was automated.
  Testing the README's quickstart as an actual consumer flake is the right fix
  and is not in this release.

---

## [Unreleased]

### Fixed

- `homeManagerModules.inspr-cli` now shell-escapes every nonempty `fleet.conf`
  value before the Bash CLI sources it. Quotes, command substitutions,
  backticks, backslashes, spaces, newlines, and dollar expansions remain
  literal data; null and empty options still emit no assignment. [INSPR-304]

### Changed

- `skills/product-gauntlet`: speed-first rewrite. One QA gate per slice (not per ticket), controller preflight, event reports instead of polling, cheaper default models, one headless Chromium at slice-end. Quality bar unchanged.

### Planned

- **NixOS VM integration tests** — `pkgs.testers.runNixOSTest` for end-to-end activation testing. Heavy but the gold standard.
- **More NixOS-equivalent modules** — server-side counterparts for the remaining HM modules (`agent-secrets`, `paimos-config`, `git-identity`). `ssh-authorized` shipped as the first NixOS module (INSPR-73). [INSPR-24 Stage 4]
- **`ssh-authorized` keyring layout** — file-per-key under `keys/<alias>.pub` for fleet-scale (~10+ keys); current inline form stays supported. [INSPR-74]
- **`ssh-authorized` build-time validation** — pipe each key through `ssh-keygen -l` (or a regex) at eval to catch typos before activation. [INSPR-75]
- **1Password tag-export integration** — Phase 2 secrets graduation (consumer-side script that materializes `.age` files from tagged 1Password items). [INSPR-23]
- **Doctor genericization** — extract Markus-specific values from `inspr-doctor` into config so the same script runs against any consumer's setup. [INSPR-44 follow-up]
- **Second-instance mirror of the cross-repo authoring doctrine** — the business-side Paimos instance should carry the same guideline as OPS #4336. Blocked on an agent credential for that instance; the `--api-key` argv path is gone (PAI-685), so it needs an interactive `paimos auth login` or a headless `PAIMOS_URL` + `PAIMOS_API_KEY` pair. [INSPR-284 follow-up]

---

## [0.3.7] — 2026-08-12

### Fixed

- **The v0.3.6 credential example was itself unverified — and wrong (INSPR-294 follow-up).** The example said the Home Assistant token is `HASS_TOKEN` in `/run/agenix/hsb1-smarthome-env`, copied from `nixcfg SMARTHOME.md`. The same session disproved it within the hour: a names-only listing of the HA container's environment shows no HA token in that file at all. The real LLAT is agenix `hsb0-openclaw-hass-token`, mounted at `/run/secrets/hass-token` in the OpenClaw containers on **hsb0** — the *consumer's* host, not the service's. The example now points at the verified location, and the pattern gained two bullets the incident earned: credentials live with their consumer, which may not be the host running the service; and repo docs go stale, so verify a credential location (names-only check or live call) before relying on it or re-documenting it. The stale nixcfg doc is NIX-355.

---

## [0.3.6] — 2026-08-12

### Added

- **The ops pack now says where host-local service credentials live (INSPR-294).** A SYSOP session asked to query the Home Assistant API on hsb1 found no token in `~/.inspr/secrets/agents/` and concluded — reasonably, on what doctrine offered — that no access path existed. It did exist: `HASS_TOKEN`, agenix-managed at `/run/agenix/hsb1-smarthome-env` on the host itself. Four layers were checked and none carried it: the kernel documents only the workstation agent-token convention (INSPR-164), the `/ops` pack had an SSH matrix but no credential access pattern, the `/secrets` pack never mentions host-local `*-env` service credentials, and the PPM `host-hsb1` runbook covers automation rules but not API access. The only documentation was `nixcfg/hosts/hsb1/docs/SMARTHOME.md`, findable by grepping a foreign repo. The ops pack now carries the pattern: per-host service tokens live at `/run/agenix/<host>-<service>-env` **on the host**, are sourced there via ssh so the value never leaves it, and the per-host variable inventory is the host's PPM runbook entry. An empty agents dir does not mean no access path exists.

### Changed

- **Done claims now require durable artifact evidence (INSPR-293 / PAI-702).** The development pack makes the completion trail explicit across code, deployments, documents, and generated assets: name the repository plus commit/range, bind a deployed release/image/digest to a live behavior check, or name the durable artifact/version. Status prose, timestamps, and “tests passed” without the result no longer count as evidence. This belongs in the development pack rather than the always-loaded kernel because it is a global delivery protocol, not a turn-1 irreversible.

---

## [0.3.5] — 2026-08-07

### Fixed

- **`DSC26` is legacy salvage, not a migration (INSPR-289).** v0.3.4 recorded `DSC26` as "moves to `pma`" on the strength of its issue counts — 29 open, activity two days prior — which read as live client work that would be stranded by a freeze. It is not: `DSC26` is the project for the server **`dsc0`**, which is being repurposed as an augmentoring host. What was wanted was a paper trail and knowledge salvage, not 76 tickets in a new home. Nothing migrated. The disposition table now says **legacy, frozen**, and the pack points at the salvage instead. Corrected within hours, before anything was moved.
- **The salvage itself.** `pma` OPS runbook `dsc0-to-amg0-salvage` carries what 76 tickets established and a rebuild would otherwise rediscover: the deploy pipeline and its two-SSH-key topology (plus the `Permission denied (publickey)` failure that means the host's deploy key was dropped from the repo, not that the deploy broke); why `system.autoUpgrade` is disabled on VPS hosts and what must be fixed before re-enabling it; the eight-step root→`mba`+sudo migration with its blocking nine-point validation before root is disabled; Pharos beacon replacing FleetCom; and the encrypted-swap label mismatch that bit during install. It also records that the host **already** runs augmentoring workloads (a Zitadel staging instance, the Pharos kernel posture collector), so the successor is not greenfield — and flags one **open security residual** to clear at handover: a live token for a decommissioned fleet system, which is precisely the kind of thing that survives a rebuild unnoticed when a box changes hands. The client and personal agent workloads on that host were deliberately **not** carried across the trust boundary; they stay with the frozen project. Target-name spelling (`amg0` as given vs the existing `agm<N>` convention) is flagged in the runbook for confirmation before it propagates into flake attrs and secrets paths.

---

## [0.3.4] — 2026-08-07

### Changed

- **Per-project dispositions for the business migration (INSPR-289).** v0.3.3 stated the routing rule but left every business project sitting on the wrong instance with only "file where the project exists" as guidance. The decision landed the same day: **a line is drawn — nothing migrates in bulk.** The five augmentoring-internal projects (`AGM`, `AMTDEL`, `AMTWEB`, `START`, `AMTCO`) are **frozen**: finish what is already open in them on `ppm`, file nothing new, and start new business work on `pma`. Two exceptions — `DSC26` **moves** (live client work, 29 open issues and activity two days before the decision; splitting it across instances would strand the open half, so the project has been created on `pma`), and `GSC26` is **archived** (0 open of 91, last activity 2026-07-23 — genuinely finished). The pack now carries this as a table, because routing by principle alone was not enough to act on.
- **`GSC26` is archived by decision, not by mechanism — and the pack says so.** Paimos has no project archive: the project entity is `{required: [name, key], optional: [description]}`, `status` is not writable through the documented API, and nothing in `/api/schema` mentions archiving. So the project will keep reporting `active` in `paimos project list` no matter what the doctrine says, and an agent picking work from the API alone cannot tell a finished project from a live one. The pack states explicitly that the table is the truth and the API is not. Feature request filed as PAI-754, covering `frozen` as well — "finish what's open, file nothing new" is likewise a real state with no representation.

---

## [0.3.3] — 2026-08-07

### Changed

- **Business work routes to the business Paimos instance (INSPR-289).** v0.3.2 named both instances but left the routing decision open, telling agents to STOP and ask whenever a task was business-side — correct while undecided, and a recurring interruption once it wasn't. Decided 2026-08-07: **business/augmentoring work belongs on `pma`, personal and INSPR work stays on `ppm`.** The pack states the rule, and the INSPR `trust-contexts` guideline's ticket-routing bullet — which had said tickets route to "the context's own **PPM** project", written when PPM was the only instance — now routes by instance as well as by project. The rule ships with the caveat that makes it usable: **migration has not happened.** All seven business projects (`AGM`, `AMTDEL`, `AMTWEB`, `START`, `AMTCO`, `DSC26`, `GSC26` — 281 issues) still live on `ppm`, while `pma` carries only `OPS`, so the doctrine says to file where the project actually exists and explicitly forbids creating a duplicate project on the other instance to satisfy the rule — a split project is worse than a temporarily misplaced ticket. Migration is INSPR-289, and it is an export/import rather than a move: `paimos issue move` reassigns between projects on one instance, but the two instances are separate deployments, so every issue key and numeric id changes and every commit message, branch name, and cross-reference pointing at them breaks. Two of the seven are client projects, which makes changing their ticket keys a coordination question and not only a technical one.

---

## [0.3.2] — 2026-08-07

### Fixed

- **The PPM pack no longer denies that a second Paimos instance exists (INSPR-288).** `AGENTS-DOMAIN-PPM.md` — the pack `/ppm` loads — asserted in two places that there is exactly one instance and, verbatim, "no routing decision to make". A second instance went live the same day (INSPR-287), so the pack was telling agents not to think about routing at precisely the moment routing became safety-relevant: the two instances **are** the personal/INSPR ↔ augmentoring boundary that the kernel's 🔴 trust-contexts rule forbids crossing with credentials or tickets. An agent that believes only one instance exists has no reason to check which one it is writing to, and `paimos` will silently create a lookalike project on the wrong side. The Endpoints section now names both instances, states that routing is a trust-context decision, and says STOP and ask when a task doesn't obviously belong to one side; the project-key table is marked `ppm`-only, since those keys do not resolve on the other instance. The retired `pmo` paragraph gained a lead-in clarifying that it is dead **and is not** the business instance — it previously read as "there was a second one, it is gone", which actively misled. Also records the two-step reality of adding an instance on a declaratively-managed workstation: `paimos auth login` seeds the keyring, but the URL must be declared in `inspr.paimos-cli.instances` or the next Home Manager switch erases it. The business instance's URL is deliberately **not** written here — this repo is public; it lives in the consumer's private config. Found by the `/tidyrepo` knowledgebase-freshness step, hours after the instance it describes came into being.

---

## [0.3.1] — 2026-08-07

### Fixed

- **The cross-repo carve-out no longer demands a review path that cannot exist (INSPR-286).** v0.3.0 made release-pin edits in a foreign repo conditional on "PR + checks — never a direct push to `main`". That condition was written from a repo which has both, and it does not generalize: vendoring v0.3.0 into the three remaining doctrine consumers hit the defect within hours. `inspr` has no CI and 1 PR in 131 commits, `amt-com` none in 88, `ops` none in 21 — zero merge commits across all three. In a single-maintainer repo with no CI, a PR the agent opens and immediately self-merges has no reviewer and no check: it satisfies the letter of the rule while delivering none of its substance, which is the very pattern the rule's own text rejects as _"the repo let me" is not review_. The condition is now two-tier — **where a review path exists, use it; where none exists, the owner's explicit request for that specific change is the gate, never agent initiative.** This still forbids the 2026-08-07 incident that produced the doctrine, because that repo *does* have a PR path and the agent was acting on its own initiative in the first place; the failure was never "no PR", it was "nobody asked". The carve-out's scope also now covers whatever a repo's documented vendoring step requires beyond the pin itself (re-mirroring a doctrine block), which the v0.3.0 wording excluded even though the procedure has always required it. Kernel 6 500 → 6 677 bytes; mirror and `KERNEL-MIRROR-OF` stamp re-synced in the same commit.

---

## [0.3.0] — 2026-08-07

### Added

- **`skills/tidyrepo`** — a third bundled skill: the cheap, state-only hygiene pass that sits below `/housekeeping`. `/housekeeping` is six phases ending in a cross-model adversarial challenge round, which is the right tool when code has drifted unreviewed for a while; after a release train its expensive phases have almost nothing to find while the *state* around the code — worktrees, branches, done-ticket metadata, backlog dupes, Knowledgebase freshness — is exactly what drifted. `/tidyrepo` is that half, cheap enough to run at the end of a working session. Boundaries are explicit so it cannot decay into "housekeeping but lazy": never a codesweep, never a challenge round, never deletes an unmerged branch, never closes a ticket, and cross-repo deletions defer to the INSPR-284 kernel rule (only branches this agent lineage created; anyone else's is a ticket, never a `git push --delete`). The load-bearing detail is branch classification: **`git merge-base --is-ancestor <branch> origin/main` reports squash-merged branches as unmerged** — squashing writes a new commit, so the branch tip is never an ancestor of main. Measured on nixcfg 2026-08-07: **32 of 45** remote branches had merged PRs that the ancestor check called unmerged. The skill asks the forge instead (`gh pr list --head "$b" --state all`) and treats "no PR found / forge unreachable" as **unknown**, not unmerged, so the delete path stays fail-safe in both directions. Bundled skills are now `ship-next`, `housekeeping`, `tidyrepo`; enrolment stays consumer-side (`inspr.agent-skills.skills.tidyrepo = { }`). [INSPR-285]

### Changed

- **Kernel: cross-repo authoring doctrine (INSPR-284).** Agents now author changes **only in the repository of the session they are running in**; everywhere else they propose — a ticket in the owning project with the diff in the body. Reading foreign repos stays unrestricted; only writes are governed. One carve-out, release pins: in a repo holding the deploy pin for what you just released you may edit only the pin and its explanatory comment, and only through that repo's normal review path (PR + checks — **never a direct push to `main`, even where `main` is unprotected**), with a recorded backup + rollback path and reversibility. Third-party / business-owned repos stop-and-ask when no PR path exists, and you clean up only your own residue. This lands in the kernel rather than a domain pack because both failures it prevents happen in turn 1, before any slash command is typed: on 2026-08-07 a PAI session rewrote `hosts/agm1/docs/RUNBOOK.md` in the business-owned `agm-nixcfg` because it had spotted stale content (correct edit, nobody who owned the repo asked for it or reviewed it), and `just deploy` there pushes straight to `main`, so it landed unreviewed — while the same day's `nixcfg` pin bumps all went through PRs with checks. "The repo let me" is not review (AGM-22). Kernel 5 494 → 6 500 bytes against the 12 000-byte budget; depth stays in OPS guideline `cross-repo-authoring-doctrine` (#4336) per the gatekeeper. The `AGENTS.md` mirror was re-synced in the same commit with its `KERNEL-MIRROR-OF` stamp updated, so Cursor / Aider / OpenCode / Codex CLI see the rule at the same moment Claude does — exactly the INSPR-269 blindness the INSPR-278 stamp check was built to prevent, and its first real exercise.

- **Profile pack no longer contradicts the ops pack on MagicDNS (INSPR-283).** `AGENTS-PROFILE-MARKUS.md` carried a 🟡 STRONG rule — _"Always use Tailscale (\*.ts.barta.cm) when LAN access does not work — works from everywhere"_ — while `AGENTS-DOMAIN-OPS.md` said the opposite: MagicDNS is OFF by Markus's permanent decision (it was breaking agent/API sessions) and those names resolve to nothing. An agent loading the profile pack was told to use addresses that return 0 answers, and the resulting `nodename nor servname provided` reads like an outage, so the agent then burns time "fixing" DNS that is off on purpose — which is exactly what happened during the 2026-08-07 penthouse outage. Rule replaced with the path that works (tailnet IP from `tailscale status`, `-p 2222` for cloud) and raised to 🔴 HARD, since following the old one wastes an outage. The generator source it cited (`nixcfg/docs/INFRASTRUCTURE.md L190`) was corrected first in nixcfg PR #281, so this will not regenerate. Live config was the other half: Headscale still had `magic_dns: true` and every fleet SSH alias resolved a dead name — fixed in nixcfg PR #285 (OPS-146).

- **inspr CLI: FleetCom checks retired (INSPR-280).** The code-side completion of INSPR-268: `inspr check` still probed `~/Code/fleetcom` (repo present, doctrine submodule, CLAUDE.md loader) although FleetCom is archived and deleted — every host failed 3 checks forever, training operators to ignore the drift tool and burying real signals. All FleetCom plumbing removed (three checks, their run_check rows, the stale heal_fix/heal_cmd mapping that survived INSPR-256's mechanical conversion, `FLEETCOM_DIR`, and the onboard clone/submodule steps). Live before/after on mbp2607: 4 permanent failures → 1, and the survivor is the genuine secrets-audit drift signal (29/30). Found by ship-next revalidation the day after the doctrine purge — the retired-system-doctrine-sweep guideline's grep applies to code too.

- **Kernel-mirror drift dies at commit time (INSPR-278).** The AGENTS.md mirror block now carries a `KERNEL-MIRROR-OF: sha256:<hash>` attestation that the re-mirror step must update, enforced by a new `kernel-mirror-stamp` flake check that recomputes the kernel hash and fails on mismatch — the exact INSPR-269 failure mode (kernel edited, mirror forgotten, non-Claude harnesses blind to a 🔴 rule for a week) can no longer merge. Editing rules updated; both check paths proven (green, and a perturbed stamp fails with the drift diagnosis). Landed as a flake check rather than an `inspr check` row deliberately: it catches drift at the source before distribution, where a host-side check would only see already-consistent vendored snapshots.

- **git-atelier: declared HM ≥25.05 floor; pretend-compat guard removed (INSPR-265).** The `hasEnableDefaultConfig` options-introspection guard advertised compatibility with older HM that the module's unconditional `programs.ssh.settings`/`programs.git.settings` usage already broke — and it hid the `enableDefaultConfig = false` opt-out block from the test stub entirely. Guard deleted, block unconditional (the outer `mkIf` already scopes to enabled ateliers), floor documented in the module header, and the formerly untestable opt-out + `"*"` defaults now have a real eval test (suite 91/91). Housekeeping NIXMOD-7, KEEP.

- **README: the `inspr` CLI exists (INSPR-273).** The packages table listed only `secrets-audit` although the flake has shipped `packages.<system>.inspr` since INSPR-195, and the Status section still described the doctor as living in a private repo pending publication. Table row added (check/heal/onboard/post-deploy), story rewritten. Housekeeping DOC-10, KEEP.

- **incident pack: lockout pointer goes somewhere real (INSPR-275).** `commands/incident.md` cited CORE topic `process/lockout-recovery`, which only exists in `AGENTS-PROFILE-MARKUS.md` — a dead pointer at the worst possible time. Now cross-references the profile file explicitly. Housekeeping DOC-12, KEEP.

- **git-atelier: unreachable validateForgeKind deleted (INSPR-264).** `forge.kind` is typed as an enum of exactly the values the runtime validator accepted, so its throw could never fire — dead validation forced via `builtins.seq` on every render, and a maintenance trap of two lists drifting apart. The validator and both forcing call sites are gone; the enum is documented as the single gate. The test header's impossible promises corrected ("Unrecognized forge.kind throws" — it cannot; "Strategy B throws not implemented" — it has been implemented and tested for a while), and a real enum-rejection test added (bogus kind fails eval via the type). Suite 90/90. Found by the 2026-08-04 /housekeeping sweep (NIXMOD-6), KEEP from the Codex adversarial challenge.

- **`inspr --help` tells the truth about heal --yes and onboard (INSPR-258).** Top-level help claimed both were "NOT YET IMPLEMENTED — see INSPR-195" although `cmd_heal` has handled `-y/--yes` and `cmd_onboard` has been a complete 10-step flow for months — self-description drift in the drift-detection tool. Annotations replaced with accurate one-liners; the rest of the help was audited against the dispatch surface and matches. New `inspr-help-surface` flake check keeps it honest: every dispatch command must appear in `--help` and any NOT-YET-IMPLEMENTED claim fails the build. Found by the 2026-08-04 /housekeeping sweep (SH-8), KEEP from the Codex adversarial challenge (incl. its smoke-test refinement).

- **post-deploy surfaces the nix-eval diagnosis on manifest failure (INSPR-259).** `inspr post-deploy` captured nix eval's stderr to a temp file that nothing ever read and the exit trap deleted — on the most failure-prone check (generated manifest evaluates) the operator got a bare ✗ while the entire explanation vanished. The failure branch now prints a labelled bounded tail (last 20 lines) of the captured stderr before cleanup. Verified live: a forced bogus-host run prints the actual flake attribute error under the ✗. Found by the 2026-08-04 /housekeeping sweep (SH-9), KEEP from the Codex adversarial challenge.

- **secrets-audit: one portable disk-scan pipeline (INSPR-257).** The GNU/BSD `find` split is gone: the BSD fallback interpolated `$SECRETS_DIR` unescaped into a `|`-delimited sed regex — a `|` in the repo path killed the audit opaquely under `pipefail`, regex metacharacters silently misparsed, and the GNU branch re-ran `find` whenever the dir was legitimately empty. Now a single `(cd "$SECRETS_DIR" && find . … | sed 's|^\./||')` with a constant pattern serves both platforms. Verified against a repo path containing both `|` and a space (clean audit) plus the functional suite. Found by the 2026-08-04 /housekeeping sweep (SH-7), KEEP from the Codex adversarial challenge (failure reproduced on BSD find).

- **license-surface no longer follows symlinks (INSPR-279).** The legacy-license scan used `grep -R`, which dereferences every symlink met during recursion — on dev machines it traversed `/nix/store` closures through `result`/`result-1` build artifacts (spurious token hits, perf sink, same commit passing in CI but failing locally depending on which artifacts exist), and the new `doctrine -> .` self-symlink (INSPR-272) raised the exposure. Lowercase `-r` scans only real files; verified in 62 ms against a checkout with all three symlinks present. Lineage: housekeeping finding SH-5, downgraded to low by the Codex challenge and shipped as exactly that.

- **module-eval failures are ordinary check failures, not flake-eval errors (INSPR-267).** The suite threw at flake-eval time, so one red unit test broke `nix flake show` and aborted check enumeration for every sibling check. The suite now returns a structured no-throw result (`{ ok; report; totalRun; totalPassed; failedTests; }`) and the `module-eval` derivation makes the pass/fail decision at build time — report in the build log and at `$out`, non-zero exit on any failure. Proven both ways: with a deliberately failing test injected, `nix flake show` enumerates cleanly and only the module-eval check fails (with a `nix log` pointer). The challenger's cross-system dedup refinement was deliberately declined: per-system eval can genuinely differ (the darwin-only stdenv recursion documented in devenv-direnv-fix.test.nix), so deduping would mask system-specific eval regressions. Found by the 2026-08-04 /housekeeping sweep (NIXMOD-9), KEEP from the Codex adversarial challenge.

---

## [0.2.0] — 2026-08-05

### Added

- **`homeManagerModules.agent-skills`** — Declarative agent-skill provisioning across CLI harnesses, plus a new top-level `skills/` directory for skills bundled with the repo. A skill (directory with `SKILL.md` at its root, per the Agent Skills convention both Claude Code and Codex scan at session start) is declared once and rendered into every configured harness skills path as read-only `/nix/store` symlinks — `~/.claude/skills/` and `~/.codex/skills/` by default; adding a harness is one `inspr.agent-skills.harnesses` attrset entry. Skills resolve to the bundled `skills/<name>/` copy when no `source` is given, or to any pinned external path (e.g. `fetchFromGitHub` of `anthropics/skills`); per-skill `harnesses` lists subset the targets (e.g. an upstream skill for Claude only). Replaces the imperative pattern this grew out of: hand-made symlink farms (`~/.agents/skills/` → per-harness links) that live in no flake, survive no rebuild, and drift silently. Bundled skills at launch: **`ship-next`** (propose + deliver the single right next change end-to-end) and **`housekeeping`** (repo/PPM hygiene sweep → codesweep → cross-agent adversarial challenge → PPM tickets → triage → ELI10 report). 7 module-eval sub-tests cover disabled shape, multi-harness rendering, per-skill subsetting, extra-harness extension, and the assertion set (empty skills, absolute harness path, undeclared harness reference).
- **`nixosModules.ssh-authorized`** — System-side counterpart to the HM `ssh-authorized` module. Same shared keyring (rich-key form with `status: active | legacy | revoked`) but renders into `users.users.<u>.openssh.authorizedKeys.keys` (which NixOS materializes as `/etc/ssh/authorized_keys.d/<u>` per the default `AuthorizedKeysFile` directive). **Multi-user**: `inspr.ssh.authorized.users.<name>.{trust, force, extraKeys}` — each user gets its own trust subset, `force` toggle (wraps the rendered list in `lib.mkForce` to displace upstream-injected keys, e.g. server-home / hokage profiles; default `false` merges via list concatenation), and `extraKeys` escape hatch for one-off raw keys that don't belong in the shared keyring. Throws at eval time on undeclared alias OR revoked-in-trust (same footgun guards as the HM module). 14 module-eval sub-tests cover disabled shape, empty-users warning, sorted-output determinism, undeclared/revoked throws, mixed string+rich keyring, multi-user rendering, force=true override, force=false merge, and extraKeys append. **Unblocks INSPR-76 RSA retirement** — flipping `status = "legacy"` → `"revoked"` in the shared keyring is now sufficient to retire across the whole fleet (no more hand-editing each host's `users.users.<u>.openssh.authorizedKeys.keys` literal). Best practice: define the keyring once in a plain-Nix file imported BOTH at NixOS-module scope (for this module) AND at HM scope (for the HM module). [INSPR-73]
- **`nixosModules.default`** — Aggregate of all NixOS modules. Convenience for consumers wanting "all of INSPR system-side" in one import.
- **NixOS-shaped test harness** — `evalNixosModule` in `tests/module-eval/harness.nix`, mirror of the existing `evalModule` (HM-shaped) but with a stub NixOS option-set covering `users.users.<u>.openssh.authorizedKeys.keys`, `warnings`, and `assertions`. Lets us exercise NixOS modules at flake-eval time without a real NixOS evaluation. Total module-eval sub-tests: 33 → 47.

- **`homeManagerModules.ssh-authorized`** — Declarative `~/.ssh/authorized_keys` management via aliased key map + trust list. Consumer declares `keys = { "alias" = "ssh-... comment"; }` and `trust = [ "alias-1" "alias-2" ]`; module renders a marker-delimited block in `~/.ssh/authorized_keys`. **Co-existence guarantee**: only the marker block is managed; lines outside it (Headscale deploy keys, GitHub Actions OIDC, recovery keys) are preserved across activations. Activation script writes the file directly (mode 0600) instead of symlinking from `/nix/store`, so OpenSSH `StrictModes` is satisfied. Trust list sorted at eval time → byte-identical output regardless of input order (no spurious git noise on rebuilds). Throws at eval time if `trust` references an alias not in `keys` (silent fall-through would be an audit-defeating footgun — sshd silently ignores empty-body lines). [INSPR-43]
- **`ssh-authorized` rich keys form** — `keys` now accepts EITHER a bare string (simple form, unchanged) OR a `{ key; status?; note?; }` submodule for grandfathering / audit. `status = "active"` (default) renders as before; `status = "legacy"` adds a `[legacy]` tag to the comment line for fleet-wide visibility (so a future inspr-doctor / FleetCom dashboard can inventory pending retirements); `status = "revoked"` is NOT admitted to authorized_keys but the declaration stays in `keys` as a historical audit record — and **throws at eval time if a revoked alias is also in `trust`** (catches the "I forgot to remove from trust" footgun). Optional `note` field appends ` (<note>)` to the comment line on any non-throwing status. Both forms accepted in the same map. 4 additional module-eval sub-tests cover legacy tagging, mixed string+rich keys, revoked-in-trust throw, and revoked-not-in-trust declaration preservation. [INSPR-77, prereq for INSPR-76 retirement workflow]
- **Module-eval test suite** — `flake.checks.<system>.module-eval` runs 33 sub-tests across the four HM modules via `lib.evalModules` + a stub HM harness (`tests/module-eval/harness.nix`). Catches regressions BEFORE `home-manager switch`: assertions firing at the right times, REQUIRED options staying required, eval-time throws still throwing, deprecated options still warning, `programs.git.includes` count for git-identity contexts, etc. Sandbox-friendly, runs on every `nix flake check`. [INSPR-72]

### Changed

- **Kernel budget: one number, one unit, everywhere (INSPR-270).** Three surfaces gave three conflicting targets: the INDEX file table still said "≤10 k chars" two sections above its own 2026-07-26 reconciliation to 12 000 BYTES, AGENTS.md carried a stale current-size annotation (8.9k), and the `/inspr` map taught "~10 k chars" plus the debunked "≤25 k combined" claim its own INDEX had refuted. All now state the single enforced truth — budget ≤12 000 bytes (`wc -c`, enforced by `inspr check`; kernel currently ~5.5 k) — with volatile current-size annotations dropped from AGENTS.md and the combined-budget line replaced by a pointer to the INDEX's measured audit record. Found by the 2026-08-04 /housekeeping sweep (DOC-5 KEEP + DOC-6 downgraded-fold), verified against the actual 5 494-byte kernel and the 12 000-byte check.

- **Domain packs are loadable inside inspr-modules itself (INSPR-272).** The upstream doctrine repo — where doctrine editing actually happens — advertised slash commands its own sessions could not use: no `.claude/commands/` existed, and every `commands/*.md` @-refs `@./doctrine/docs/...`, a path that only resolves in consuming repos. Fixed by self-consumption: `.claude/commands/*` now symlink to the canonical `commands/*` files (the exact pattern consumers use), and a `doctrine -> .` self-symlink makes the consumer-form paths resolve in-repo — one layout everywhere, no duplicated command content. Verified the self-symlink survives the flake source closure and the license/location surface checks. CLAUDE.md documents the mechanism. Found by the 2026-08-04 /housekeeping sweep (DOC-9), KEEP from the Codex adversarial challenge.

- **`/iac` appears in every command map (INSPR-271).** The kernel router has listed `/iac` since the pack landed, `commands/iac.md` exists and is symlinked in all consuming repos — but the `/inspr` TL;DR map's slash-command table, AGENTS.md's domain-pack architecture row, the kernel-mirror footer's load-a-pack command list, and CLAUDE.md's loader comment all omitted it, so agents navigating by the map never loaded the 8.3k IAC doctrine before Terraform/Zitadel/Cloudflare work. All four surfaces now list `/iac` (`AGENTS-DOMAIN-IAC.md` — L5 declarative services). Found by the 2026-08-04 /housekeeping sweep (DOC-7), KEEP from the Codex adversarial challenge, incl. its CLAUDE.md-sync refinement.

- **module-eval: agent-secrets discovery finally has real fixtures (INSPR-266).** The fixture directories were empty and untracked — git cannot track empty dirs, so in the flake source closure they didn't exist at all and every agent-secrets test silently exercised the missing-dir branch: discovery, expected-basename rendering, shared-vs-host precedence, and the `requireFiles` eval-time throw (the module's flagship untracked-file guard) had zero coverage, and `fixtures/with-secrets` sat as abandoned scaffolding. Now committed: dummy `.age` fixtures (names are the payload; nothing is ever decrypted at eval) including a shared/host `COLLIDE.age` pair, a `bad-names` fixture whose space-bearing filename proves the INSPR-263 alphabet validation throws, and a `.gitkeep` so `empty-secrets` tests the dir-exists-but-empty branch instead of the missing-dir branch. 6 new sub-tests: discovery renders both scopes, host wins collisions (shared decrypts first, host last — now documented behavior), requireFiles passes/fails correctly, bad names fail eval, and the empty fixture still renders the full lifecycle script. Suite 89/89. Found by the 2026-08-04 /housekeeping sweep (NIXMOD-8), KEEP from the Codex adversarial challenge.

- **agent-secrets: retired decryptedDir locations are checked for plaintext residue (INSPR-262).** The module's own default flip (≤2026-05-12: `~/Secrets/age/decrypted/agents/` → INSPR-164's `~/.inspr/secrets/agents/`) left every previously decrypted plaintext secret sitting at the old path forever — orphan cleanup only ever scanned the current dir, so nothing tracked, rotated, or cleaned the residue. New `retiredDirs` option (default: the pre-INSPR-164 path) makes activation emit a loud multi-line warning when a retired dir that differs from the current `decryptedDir` still contains `*.env` files — warn ONLY, never delete: the files are secrets and disposal is the operator's explicit call (challenger-refined). The check runs before the identity requirement so it fires even when the rest of activation fails; consumers pinning the legacy path deliberately are skipped by the inequality guard, and `retiredDirs = [ ]` silences it. 2 new module-eval sub-tests (suite 83/83) plus a rendered-script behavioral proof against a synthetic residue dir. Found by the 2026-08-04 /housekeeping sweep (NIXMOD-4), KEEP from the Codex adversarial challenge.

- **agent-secrets: escaped interpolation + exact orphan matching (INSPR-263).** The activation script interpolated `decryptedDir`, source paths, and the expected-basenames set raw (paimos-config escapes everything and ships injection tests; this module did not): quotes or `$(` in a config value turned typos into code execution at activation, and the space-delimited orphan matcher was corruptible — a secret named `FOO BAR.age` made the glob `*" BAR.env "*` match, so a genuinely orphaned `BAR.env` was silently kept, breaking the one-way lifecycle guarantee. Now: secret basenames are validated at eval time against `[A-Za-z0-9_][A-Za-z0-9_.-]*` (dashes stay allowed — materialized SSH key names use them; shell metacharacters throw with a rename instruction), `decryptedDir`/source paths/expected set go through `lib.escapeShellArg`, and orphan cleanup matches exact whole lines via `grep -Fxq` against a newline list. The `$HOME`-expanding `identityFiles` interpolation is kept and marked as the single deliberate exception. Module-eval suite stays 81/81. Found by the 2026-08-04 /housekeeping sweep (NIXMOD-5), KEEP from the Codex adversarial challenge; completes the `shell-interpolation-hygiene` KB guideline's open examples (with INSPR-255/256).

- **ssh-authorized refuses to rewrite when the end marker is missing (INSPR-261).** If the begin marker matched but the end marker never did, the awk splice silently discarded every line after the begin marker — including manual entries BELOW the managed block (Headscale deploy keys, break-glass recovery keys) that the module's coexistence guarantee promises to preserve; on a remote host that can be an SSH lockout. The END-block comment even blessed the truncation as "the right outcome". The splice now detects EOF inside an unterminated block, prints a repair instruction, and exits non-zero — activation aborts before the atomic move, so the original file stays untouched. New functional check `ssh-authorized-functional` executes the rendered activation against synthetic authorized_keys files: fresh host, valid-marker replacement preserving manual lines above AND below, missing-end-marker failure with byte-identical original, and substring-only markers (which never truncated — the outer grep is substring, awk is exact-line — now proven). Found by the 2026-08-04 /housekeeping sweep (NIXMOD-3), KEEP from the Codex adversarial challenge.

- **`inspr heal` executes typed fix functions, never display strings (INSPR-256).** Heal actions were built by interpolating env-derived paths (`$NIXCFG_DIR`, `$SECRETS_DIR`, … — commonly set by direnv) into single-quoted command strings executed via `bash -c`; a single quote in such a path broke out of the quoting and executed arbitrary trailing text (reproduced live by the Codex adversarial challenge), with no prompt at all under `--yes`. The contract is now split: `heal_fix_<slug>` emits tier + a display-only string, and a typed executable twin `heal_cmd_<slug>` runs the fix directly as argv — paths are ordinary quoted arguments, never re-parsed by a shell. `_heal_apply` refuses auto/confirm mappings without an executor (counts as failed, script bug). Regression harness extended to 6 paths including a hostile `SECRETS_DIR` containing a quote + payload: literal `chmod 500` applies, nothing injected runs. Found by the 2026-08-04 /housekeeping sweep (SH-6); closes the second of the two reproduced injection vectors (with INSPR-255).

- **Pharos registration validates the bootstrap token before building the request (INSPR-255).** The bootstrap/registration token flowed from `INSPR_PHAROS_REGISTRATION_TOKEN` into the curl `--config` heredoc with only an emptiness check — the config parser treats quotes and newlines as syntax, so a double quote truncated the Authorization header and an embedded newline injected arbitrary curl directives (`output=`/`url=`/`write-out`), turning a poisoned env var into a file-write or token-exfiltration vector (reproduced live by the Codex adversarial challenge). New `_validate_bootstrap_token` rejects anything outside a conservative token alphabet (`A-Za-z0-9 . _ ~ + / = -`) before curl can run; the error names the rule, never the value. 9-case regression harness including a stubbed-curl proof that curl is never invoked for a malformed token. Found by the 2026-08-04 /housekeeping sweep (SH-3).

- **git-atelier: Strategy-B ateliers get their managed known_hosts file (INSPR-260).** The Strategy-B (userKey) match block sets `UserKnownHostsFile` to `~/.ssh/known_hosts.d/inspr-git-atelier-<name>` whenever `manageKnownHosts = true`, but both the file renderer and the empty-file warning were guarded on `deployKeys != {}` — so a userKey-only atelier (the module's canonical workstation answer) pointed SSH at a file that never materialized: interactive first connections fell back to a trust prompt, noninteractive ones failed host-key verification, and no warning fired. Both guards now accept `deployKeys != {} || userKey != null`. Covered by a new module-eval regression test (userKey-only atelier renders the file, with built-in github.com keys, and the matchBlock references it); suite now 81/81. Found by the 2026-08-04 /housekeeping sweep (NIXMOD-2), KEEP from the Codex adversarial challenge.

- **FleetCom purged from live doctrine; consumer-set lists reconciled (INSPR-268).** The OPS pack (loaded by `/ops` and `/incident`) still taught "Query FleetCom (`fleet.barta.cm`) as the canonical live source for fleet inventory" a month after archival — inventory is now **Pharos** (<https://pharos.barta.cm>, `pharosd` on csb1; HostDash renders the human view), with an explicit never-query-`fleet.barta.cm` note. The `/inspr` map no longer points fleet inventory at the nonexistent `~/Code/fleetcom` repo, and `/pushall` + the DEV pack + `AGENTS.md` + the INDEX + nine role-overlay headers now agree on ONE doctrine-vendoring set: `inspr-modules → nixcfg → inspr → amt-com → ops` (previously three surfaces gave three different four-repo lists, silently leaving amt-com and ops on stale doctrine after every kernel change). Historical provenance references (`src: ~/Code/fleetcom/...` harvest footnotes, phase-history rows) are deliberately retained. Found by the 2026-08-04 /housekeeping sweep (DOC-1/2/3), all KEEP from the Codex adversarial challenge.

- **`inspr heal` no longer reports success when its fixes fail (INSPR-254).** A failed fix application (auto or confirm tier) previously incremented no counter, so a run where every mapped fix failed still printed "0 applied, 0 deferred, 0 need manual action" and exited 0 — automation consuming the exit code believed the host was healed when nothing changed. Heal now (1) counts every failed application in a new `fix_failed` counter (unknown-tier script bugs included), (2) verifies each "applied" claim by re-running the failed `check_<slug>` after the command succeeds — a fix whose command exits 0 but whose check still fails counts as failed, not healed (check exit 77/skip counts as healed; a vanished check function stays unverifiable-but-applied), (3) shows `N failed` in the summary line, and (4) exits non-zero whenever `fix_failed > 0`. Found by the 2026-08-04 /housekeeping sweep (SH-1), KEEP verdict + re-run refinement from the Codex adversarial challenge; behavior covered by a 6-path harness test of `_heal_apply`.

- **Kernel mirror re-synced (INSPR-269).** The `AGENTS.md` KERNEL-MIRROR block — the only kernel surface tools like Codex CLI, Cursor, and Aider ever see — had not been re-mirrored after the 2026-07-26 kernel rewrites. Added the missing 🔴 **trust-contexts** rule (personal / INSPR / augmentoring classified by ownership of the output; never cross contexts with credentials or tickets — a turn-1 irreversible that previously never reached non-Claude harnesses), added `strings` to the secret-file read ban and `docker inspect` to the resolved-environment ban, and carried over the kernel's "apply the principle, not just the literal list" clause. Found by the 2026-08-04 /housekeeping sweep (DOC-4), KEEP verdict from the Codex adversarial challenge; the challenger's automated mirror-drift-check refinement is tracked separately.

- **Ops pack: MagicDNS is permanently OFF.** The SSH access matrix told agents to reach hosts via `*.ts.barta.cm` ("works from everywhere"). Markus disabled MagicDNS deliberately and indefinitely because it was breaking agent sessions, so those names resolve to nothing — the doctrine was actively sending agents down a dead path, and the failure (`nodename nor servname provided`) reads like an outage. Matrix now says: address tailnet hosts by **IP**, obtained from `tailscale status`, never hardcoded and never assumed static; `-p 2222` still applies to csb0/csb1 on the tailnet; and an explicit "this is expected, do not debug DNS" note. Same rule cross-referenced from the Tailscale/Headscale topology section. Also dropped two stale rows the matrix still advertised: the **imac0 exception** (imac0 + imacw are decommissioned, OPS guideline `imac-fleet-decommissioned`) and **gpc0** in the LAN host list (retired 2026-07 → stm2607). Added a note that a retired host can linger as a tailnet node long after its config is gone — Headscale removal is its own teardown step.

- **Second sweep — kernel 7 334 → 5 494 bytes.** A pass over the *combined* auto-load surface (kernel + per-repo delta), not just the kernel. Router 1 713 → 739: the table's "If you're about to… Edit nix-darwin / Home Manager / devenv / NixOS module → `/nix`" prose collapsed to a compact `·`-separated line, keeping the per-pack size warning because that is the part agents need *before* loading. Editor-facing meta 1 168 → 353: the HTML preamble and Gatekeeper stub speak to whoever edits the kernel, and the full text already lives in `AGENTS-INDEX.md` — every agent was paying for it every turn. Identity & protocol compressed without dropping Style / Pacing / Time / Default; trust-contexts keeps the 🔴 crossing rule inline and points at the guidelines for classification detail. Verified no rule or token was lost before committing. Also cross-linked INSPR guidelines `trust-contexts` (repos and code) ↔ `domain-separation-barta-vs-augmentoring` (domains and services) — the same personal/business split on two axes, previously unlinked.

- **Kernel budget audit — 9 997 → 7 334 bytes, no rule lost.** Every rule in the old kernel is either still present or already existed verbatim in the pack it was demoted to (verified mechanically before removal). Highlights: **5 of 9 router size estimates were wrong**, all understating — `/style` claimed 20k but loads 46k, `/incident` claimed 5k but loads 20k, `/ppm` 8k → 22k, `/ops` 12k → 18k, `/dev` 8k → 11k; the per-row column was replaced with one accurate "heavy ones" line. **6 🟡 rules that violated the kernel's own "turn-1 irreversibles only" gatekeeper were removed** — `gh pr view/diff`, push-is-normal-flow, multi-agent stash, `git config --global` (all already in `/dev`) and the PPM keyring paragraph (`/ppm` covers it in more depth); `zellij, NOT tmux` lived only in the 46k `PROFILE-MARKUS`, so it moved to `/dev` instead of being dropped. **~20 % of the kernel described the kernel** — gatekeeper rule, cross-reference footer and per-repo-deltas paragraph moved to `AGENTS-INDEX.md`; the purpose statement appeared three times and the secret-read ban twice, both deduplicated. **Budget reconciled**: the header claimed `≤ 10 000 chars` while the only enforcement (`inspr check`) was `12 000` **bytes** — now one number, one unit, with the multibyte-emoji trap documented. Stale scope fixed: the header listed consumers as "nixcfg, inspr, fleetcom, inspr-modules", omitting `ops` and naming `fleetcom`, which the kernel body declares archived. Headroom restored from 3 bytes to 4 666.

- **Kernel: trust contexts are now always-on doctrine** — the `Umbrella` bullet in `docs/AGENTS-KERNEL.md` became `Umbrella & trust contexts`. Every repo is exactly one of **personal** (Markus's own infra + hobby projects), **INSPR** (the FOSS project, org `inspr-at`), or **augmentoring** (INSPR's business side — commercial/client work, e.g. `dsccfg`). Classification follows **ownership of the output**, explicitly **not** the GitHub org, because the orgs do not match the split: no `augmentoring` org exists yet, `amt-com` and `dsccfg` still sit under `markus-barta/`, and 5 of 9 `inspr-at` repos are private. Carries one hard rule — 🔴 never cross contexts with credentials or tickets (`dsccfg` → `DSC26`, personal fleet → `OPS`); STOP and ask. Promoted to kernel rather than a domain pack because cross-context credential leakage is a turn-1 irreversible and the rule must reach agents in *every* repo, including ones that never load `/ops`. Full classification table and migration plan live in the INSPR PPM guideline `trust-contexts`. ⚠️ **The kernel is now at 9 997 / 10 000 chars — 3 chars of headroom.** The next addition must trim something first; merging into an adjacent bullet (as done here) is the pattern that fits. Decided 2026-07-26.
- **Repository license is now AGPL-3.0-only** - canonical legal text, Nix
  package metadata, module headers, public documentation and licensing doctrine
  now share one exact identifier. Existing grants on earlier revisions remain
  valid; the new license boundary begins with INSPR-236.
- **`homeManagerModules.paimos-config` now manages routing only** — generated `~/.paimos/config.yaml` contains `default_instance` and instance URLs, never `api_key`. Existing literal `url` and `urlEnvFile` + `urlVar` routing sources remain supported; runtime URLs are encoded through an explicit jq store path so quotes, CR/LF, backslashes, and control characters cannot corrupt YAML. Missing/empty routing input fails before the atomic move and preserves the prior config. INSPR workstations authenticate interactively with `paimos auth login` into the OS keyring; headless automation injects `PAIMOS_URL` + `PAIMOS_API_KEY` into the process from approved encrypted storage. The old `apiKeyEnvFile` and `apiKeyVar` options remain accepted for one compatibility release but are ignored and emit an evaluation warning—this is evaluation-only compatibility, not credential migration. A non-printing structural guard refuses to replace an existing legacy `api_key` config until `paimos auth whoami` runs with all auth overrides unset and performs the Paimos 4.8 migration. Migration must happen before any new interactive login so the old inline credential cannot overwrite a newly entered keyring credential. Structural and executable regressions prove nested YAML, fail-before-replace behavior, shell-safe diagnostics, legacy-config preservation, and absence of configured credential-file/variable markers from activation. [INSPR-225]

### Fixed

- **`paimos-config` is now independently consumable** — previously referenced `config.inspr.secrets.agents.enable` directly, which failed eval (`attribute 'secrets' missing`) when `paimos-config` was imported without `agent-secrets`. Now uses `config.inspr.secrets.agents.enable or false` — modules can be picked à la carte. (Found by INSPR-72 module-eval suite — the kind of regression module-level eval catches that integration tests miss.)

---

## [0.1.0] — 2026-05-02

Initial Pattern β extraction from [markus-barta/nixcfg](https://github.com/markus-barta/nixcfg).

### Added

- **`homeManagerModules.agent-secrets`** — Materialize agenix-encrypted env files into a per-user "agent-exception" directory at HM activation. Universal contract; consumer provides `encryptedRoot` (path), and the module handles discovery + decryption + lock-after-activation.
- **`homeManagerModules.git-identity`** — Multi-identity git config with `gitdir:` AND `hasconfig:remote.*.url:` includeIf rules. Consumer declares `identities` (named) and `contexts` (per-context overrides, by either gitdir or remote URL pattern). The repo's own remote URL picks the identity automatically.
- **`homeManagerModules.paimos-config`** — Auto-bootstrap `~/.paimos/config.yaml` from agent-secrets-materialized API key files. Consumer declares `instances` (named) and `defaultInstance`.
- **`homeManagerModules.default`** — Aggregate of all three above; convenience for consumers wanting "all of INSPR" in one import.
- **`packages.<system>.secrets-audit`** — Nix-derivation-packaged bash script that detects drift between `secrets/*.age` files and their declarations in `secrets/secrets.nix`. Three modes: human report, `--quiet`, `--json`.

### Fixed (during initial extraction + day-of audit pass)

- **`agent-secrets.encryptedRoot` is REQUIRED** — was a misleading default (`../../secrets/agents` relative to the module file, which broke immediately on consumers whose layout differed). Now consumers must declare it explicitly. Loud failure beats silent emptiness. (commit `fd001ce`)
- **Activation security regression** — `agent-secrets` now uses `trap chmod 0500 EXIT` to GUARANTEE the decrypted dir is relocked on ANY activation exit path, not just the happy path. Without this, a mid-decrypt failure would leave the dir at 0700 (writable) until next successful activation. (closes audit finding H4)
- **YAML injection vector** — `paimos-config` api_key values are now written as YAML single-quoted scalars with proper `'` → `''` escaping. Previously written unquoted, which would break parsing on values containing leading `*`/`&`/`[`/`{` or embedded `:` `#`. (closes audit finding H1)
- **Eval-time assertions** — `paimos-config` now asserts `defaultInstance ∈ instances` AND `instances ≠ {}` at switch time. Misconfig fails loudly, not silently at paimos CLI runtime. (closes audit findings H3 + O6)
- **Tmpfile cleanup** — `paimos-config` activation now uses `trap rm -f EXIT` to clean up the YAML tmpfile on any failure. No more dotfile garbage in `~/.paimos/`. (closes audit finding H2)
- **Hostname silent-default footgun** — `agent-secrets` now throws a clear eval-time error if hostname can't be determined (was: literal string `"$(hostname -s)"` which silently produced zero host-specific secret discovery). New explicit `hostname` option as alternate path. (closes audit finding C8)
- **`secrets-audit` packaging** — switched from `mkDerivation + postFixup-sed-injection` to `writeShellApplication`. The previous form broke `--help` (the PATH-export sed injection collided with the help-extraction sed). Now `--help` is clean; closure is automatic-minimum; shellcheck runs at build time. (closes audit findings C7 + H6 + M2 + O4)

- **Functional test suite** — `flake.checks.<system>.secrets-audit-functional` runs 7 sub-tests: drift detection across 4 fixtures (clean / declared-missing / orphan / commented-out) plus a `--help` regression test for INSPR-50/C7. Sandbox-friendly, runs on every `nix flake check` + every CI push. (closes audit finding O1, partial — module-eval tests deferred to INSPR-72)

- **GitHub Actions CI** — `.github/workflows/check.yml` runs `nix flake check --all-systems` on push + PR + manual trigger; cross-builds `secrets-audit` on Ubuntu + macOS; includes a regression test that `--help` doesn't leak the PATH export. (closes audit finding O2)

### Documentation

- **CHANGELOG.md** (this file) — keepachangelog.com format. (closes audit finding O3)
- **README** — added "Testing" section (how to run + roadmap), "Versioning + deprecation policy" section (semver interpretation + 1-MINOR-cycle deprecation window), "Recovery scenarios" table (9 common failure modes + fixes). (closes audit findings O5 + O7)
- **All module headers + option descriptions** stripped of Markus-specific identifiers, paths, and roadmap details. Public-library-appropriate framing throughout. (closes audit findings C1 + C2 + C3 + C4 + C6)

### Changed

- **`paimos-config.instances` default is `{}`** (was `ppm = { ... }` Markus-specific). Consumers MUST declare their own instances; no sensible cross-context default for a public library.
- **`git-identity` accepts `identities` + `contexts` as options** (was hardcoded Markus-personal + former-work values). Universal mechanics; per-consumer values.
- **All module documentation** — stripped Markus-specific identifiers, paths, and roadmap details from module source. Public-library-appropriate framing throughout.

### Provenance

Extracted from the INSPR onboarding sessions of 2026-05-01 and 2026-05-02:
- Day 1: M5 (mbp0) onboarded; agent-secrets + git-identity patterns established
- Day 2 morning: paimos-config added; inspr-doctor v2 (host-class profiles) shipped
- Day 2 afternoon: Pattern β extraction (this v0.1.0); audit pass + 18 fixes

See the (private) [inspr](https://github.com/markus-barta/inspr) umbrella repo for the narrative playbook.
