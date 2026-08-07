# AGENTS — Profile: Markus Barta

*Layer: `profile:markus` · Synthesized 2026-05-14 by INSPR-179 Phase 4 · This layer holds 153 rules.*

This document is the authoritative source for Markus Barta's personal preferences — applied on top of CORE whenever an agent is operating as/for Markus. Other layers (read top-down for full context):

- **[AGENTS-CORE.md](./AGENTS-CORE.md)** — universal rules every agent follows
- **[AGENTS-PROFILE-MARKUS.md](./AGENTS-PROFILE-MARKUS.md)** — Markus Barta's personal preferences
- **AGENTS-AGENT-*.md** — per-role overlays (one per agent identity)
- **per-repo AGENTS.md** in nixcfg/inspr/amt-com/ops — repo-specific deltas

---

## Topic: security/destructive-ops

- 🔴 **HARD** | `dont` | Do not touch prior user's home directory, LaunchDaemons/LaunchAgents, or login items without explicit instruction during the 30-day policy window
  *<sub>src: ~/.claude/.../memory/project_machine_mbp_provenance.md L15</sub>*
  <!-- rule_ids: project_machine_mbp_provenance.md:L15:do-not-touch-prior-user-state | cluster: — -->


## Topic: security/secrets-output

- 🟡 **STRONG** | `never` | Do not contact, mention publicly, or attribute decisions to Patrizio externally without the user's say-so
  *<sub>src: ~/.claude/.../memory/reference_patrizio_pbek.md L17</sub>*
  <!-- rule_ids: reference_patrizio_pbek.md:L17:no-public-attribution-without-consent | cluster: — -->


## Topic: security/ssh-keys

- 🔴 **HARD** | `never` | Never delete a key from a host without confirming it's not the only admittance there — grep first; then ask
  *<sub>src: ~/Code/inspr/legacy-rsa-key-inventory.md L240</sub>*
  <!-- rule_ids: legacy-rsa-key-inventory.md:L240:never-delete-key-without-confirming-not-only | cluster: — -->

- 🔴 **HARD** | `never` | Never reuse the same alias for a different key; if a new RSA replacement is generated, give it a new alias (e.g. markus-rsa-2026), not a re-binding
  *<sub>src: ~/Code/inspr/legacy-rsa-key-inventory.md L241</sub>*
  <!-- rule_ids: legacy-rsa-key-inventory.md:L241:never-reuse-alias-for-different-key | cluster: — -->

- 🟡 **STRONG** | `always` | For fleet-scale host-key trust, treat the longest-running and most-trusted workstation as authoritative; cross-reference against it before adding keys to any other workstation
  *<sub>src: ~/Code/inspr/playbook.md L559</sub>*
  <!-- rule_ids: playbook.md:L559:cross-reference-known-hosts-from-trusted-workstation | cluster: — -->

- 🟡 **STRONG** | `never` | Never assume the inventory of key admittance is complete; always re-grep before retiring — new admittances may have been added since last update
  *<sub>src: ~/Code/inspr/legacy-rsa-key-inventory.md L243</sub>*
  <!-- rule_ids: legacy-rsa-key-inventory.md:L243:never-assume-inventory-complete | cluster: — -->


## Topic: incident-response/secret-leak

- 🔴 **HARD** | `always` | In .envrc glob-source loops, use a content-aware filter (e.g. head -c 64 | grep KEY=VALUE format) to admit only env-var files; SSH keys silently skipped
  *<sub>src: ~/Code/inspr/playbook.md L1015-1016 · incident: Day-11</sub>*
  <!-- rule_ids: playbook.md:L1015:envrc-content-aware-filter | cluster: — -->


## Topic: secrets/access-pattern

- 🔴 **HARD** | `always` | Source agent secret env files via 'set -a; . <file>; set +a' for KEY=value content; NEVER cat/sed/head these files
  *<sub>src: ~/Code/inspr/RESUMING-2026-05-12.md L347</sub>*
  <!-- rule_ids: RESUMING-2026-05-12.md:L347:secrets-source-not-cat | cluster: — -->

- 🟡 **STRONG** | `do` | After decrypting tier 3 secret to disk, chmod 600 the decrypted file
  *<sub>src: ~/Code/nixcfg/docs/SECRETS.md L353-357</sub>*
  <!-- rule_ids: SECRETS.md:L356:chmod-600-on-decrypted-secrets | cluster: — -->

- 🟡 **STRONG** | `do` | Auto-materialized agent secrets live at /Users/<u>/.inspr/secrets/agents/<NAME>.env (canonical fleet-wide, INSPR-164)
  *<sub>src: ~/Code/nixcfg/docs/SECRETS.md L130-131 · incident: INSPR-164</sub>*
  <!-- rule_ids: SECRETS.md:L130:agent-secrets-canonical-path | cluster: — -->

- 🟡 **STRONG** | `do` | Daily interface for agent secret env files: ( set -a; source <file>; cmd; set +a )
  *<sub>src: ~/Code/nixcfg/docs/SECRETS.md L134</sub>*
  <!-- rule_ids: SECRETS.md:L134:agent-secrets-source-pattern | cluster: — -->

- 🟡 **STRONG** | `dont` | Do not assume secrets have been provided; the user wants alignment on the vision before sharing them
  *<sub>src: ~/.claude/.../memory/project_onboarding_initiative.md L19</sub>*
  <!-- rule_ids: project_onboarding_initiative.md:L19:dont-assume-secrets-provided | cluster: — -->


## Topic: secrets/agenix-pipeline

- 🔴 **HARD** | `always` | Every agents/* .age file MUST include the user as an AGE recipient because HM-standalone activation cannot read root-owned host keys
  *<sub>src: ~/Code/inspr/playbook.md L420</sub>*
  <!-- rule_ids: playbook.md:L420:agents-include-user-as-recipient | cluster: — -->

- 🔴 **HARD** | `never` | Never remove a recipient from AGE recipients without rekeying first — this is the highest-risk delete in the inventory
  *<sub>src: ~/Code/inspr/legacy-rsa-key-inventory.md L242</sub>*
  <!-- rule_ids: legacy-rsa-key-inventory.md:L242:never-remove-from-age-recipients-without-rekeying | cluster: — -->

- 🟡 **STRONG** | `do` | Adding a new secret: encrypt with AGE, commit .age file, declare in nix module, rebuild, file appears at /run/agenix/<name>
  *<sub>src: ~/.claude/.../memory/reference_secrets_agenix.md L13</sub>*
  <!-- rule_ids: reference_secrets_agenix.md:L13:agenix-add-secret-flow | cluster: — -->

- 🟡 **STRONG** | `dont` | Do not suggest sops, pass, 1Password CLI, env-var-in-shell, or other parallel secret stores unless user explicitly asks to compare
  *<sub>src: ~/.claude/.../memory/reference_secrets_agenix.md L12</sub>*
  <!-- rule_ids: reference_secrets_agenix.md:L12:no-alternative-secret-stores | cluster: — -->

- 🟢 SOFT | `dont` | Don't keep flagging the SSH-host-key-as-AGE-recipient bootstrap as a novel problem; check the existing workflow first
  *<sub>src: ~/.claude/.../memory/reference_secrets_agenix.md L14</sub>*
  <!-- rule_ids: reference_secrets_agenix.md:L14:dont-flag-bootstrap-as-novel | cluster: — -->


## Topic: secrets/credentials-storage

- 🟡 **STRONG** | `always` | Default to per-host 1Password entries for any infra credential — never reuse names that imply broader coverage than they actually have
  *<sub>src: ~/Code/inspr/playbook.md L520</sub>*
  <!-- rule_ids: playbook.md:L520:per-host-1p-entries | cluster: — -->


## Topic: style/communication

- 🟡 **STRONG** | `do` | At step done/crossroad/blocker, show TL;DR-style bullet list using GitHub checkbox notation: - [x] for done, - [ ] for not done, with (in progress) on active item
  *<sub>src: ~/.claude/.../memory/project_onboarding_initiative.md L25</sub>*
  <!-- rule_ids: project_onboarding_initiative.md:L25:status-checkpoint-checkbox-convention | cluster: — -->

- 🟡 **STRONG** | `do` | Default to private repos for anything in this initiative until the user explicitly says to publish
  *<sub>src: ~/.claude/.../memory/feedback_external_framing.md L12</sub>*
  <!-- rule_ids: feedback_external_framing.md:L12:default-private-repos | cluster: — -->

- 🟡 **STRONG** | `do` | Defend INSPR register against motivational-poster / wellness-brand drift; keep tone clear-eyed and serious, never aspirational-fluffy
  *<sub>src: ~/.claude/.../memory/project_inspr.md L103</sub>*
  <!-- rule_ids: project_inspr.md:L103:defend-against-poster-drift | cluster: — -->

- 🟡 **STRONG** | `dont` | Do not write anything that reads as a competitive critique of his current company or its market
  *<sub>src: ~/.claude/.../memory/feedback_external_framing.md L14</sub>*
  <!-- rule_ids: feedback_external_framing.md:L14:no-competitive-critique | cluster: — -->

- 🟡 **STRONG** | `dont` | Don't optimize purely for 'easy to install today' if it makes daily use awkward
  *<sub>src: ~/.claude/.../memory/feedback_tool_selection.md L12</sub>*
  <!-- rule_ids: feedback_tool_selection.md:L12:prefer-pro-easy-once-setup | cluster: — -->

- 🟡 **STRONG** | `dont` | Don't propose tools elegant in theory but fragile or DIY in practice
  *<sub>src: ~/.claude/.../memory/feedback_tool_selection.md L13</sub>*
  <!-- rule_ids: feedback_tool_selection.md:L13:dont-propose-fragile-elegant | cluster: — -->

- 🟡 **STRONG** | `do` | For long answers, place TL;DR at both beginning and end
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L10 · ~/Code/nixcfg/+agents/rules/AGENTS.md L11</sub>*
  <!-- rule_ids: AGENTS.md:L10:long-answers-tldr-both-ends,AGENTS.md:L11:short-answers-tldr-end | cluster: style-communication-007 -->

- 🟡 **STRONG** | `do` | For very short answers, omit TL;DR entirely
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L12</sub>*
  <!-- rule_ids: AGENTS.md:L12:very-short-no-tldr | cluster: — -->

- 🟡 **STRONG** | `do` | Frame README copy, commit messages, and public-facing prose as personal exploration / mission-driven open source / craft work, not as a startup or commercial venture
  *<sub>src: ~/.claude/.../memory/feedback_external_framing.md L13</sub>*
  <!-- rule_ids: feedback_external_framing.md:L13:framing-personal-mission | cluster: — -->

- 🟡 **STRONG** | `do` | Frame technical discussion at senior engineer/founder level; skip beginner caveats unless topic is outside core software engineering
  *<sub>src: ~/.claude/.../memory/user_profile.md L13</sub>*
  <!-- rule_ids: user_profile.md:L13:senior-framing | cluster: — -->

- 🟡 **STRONG** | `dont` | INSPR is the umbrella; Paimos is a tool inside it; do not conflate them in copy or hierarchy
  *<sub>src: ~/.claude/.../memory/project_inspr.md L101</sub>*
  <!-- rule_ids: project_inspr.md:L101:dont-conflate-inspr-paimos | cluster: — -->

- 🟡 **STRONG** | `prefer` | Prefer tools with real ecosystem, declarative/reproducible config, and track record over scrappy one-off solutions
  *<sub>src: ~/.claude/.../memory/feedback_tool_selection.md L14</sub>*
  <!-- rule_ids: feedback_tool_selection.md:L14:prefer-real-ecosystem-tools | cluster: — -->

- 🟡 **STRONG** | `prefer` | Refer to the departed colleague only when operationally necessary; otherwise use 'the prior user' or 'the policy window'
  *<sub>src: ~/.claude/.../memory/project_machine_mbp_provenance.md L11</sub>*
  <!-- rule_ids: project_machine_mbp_provenance.md:L11:minimize-prior-user-references | cluster: — -->

- 🟡 **STRONG** | `do` | Render wordmark as INSPR not inspr.at; reserve the dotted form for URL contexts only
  *<sub>src: ~/.claude/.../memory/project_inspr.md L102</sub>*
  <!-- rule_ids: project_inspr.md:L102:render-as-INSPR-not-url | cluster: — -->

- 🟡 **STRONG** | `do` | TL;DR placement: long answers at beginning AND end; short only at end; very short no TL;DR; syntax 'TL;DR: <summary>'
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L13-17</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L14:tldr-placement | cluster: — -->

- 🟡 **STRONG** | `always` | Telegraph style: long answers TL;DR at start AND end; short answers TL;DR at end; very short no TL;DR
  *<sub>src: ~/Code/inspr/RESUMING-2026-05-12.md L348</sub>*
  <!-- rule_ids: RESUMING-2026-05-12.md:L348:telegraph-style-tldr-rules | cluster: — -->

- 🟡 **STRONG** | `do` | Telegraph style: noun phrases ok, min grammar, min tokens, friendly tone
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L12</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L12:telegraph-style | cluster: — -->

- 🟡 **STRONG** | `do` | Use TL;DR syntax "TL;DR: <summary>" with leading pin emoji
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L13</sub>*
  <!-- rule_ids: AGENTS.md:L13:tldr-syntax | cluster: — -->

- 🟡 **STRONG** | `do` | When in doubt about copy that might go public, ask the user before committing
  *<sub>src: ~/.claude/.../memory/feedback_external_framing.md L15</sub>*
  <!-- rule_ids: feedback_external_framing.md:L15:ask-before-public-copy | cluster: — -->

- 🟡 **STRONG** | `do` | When working on Paimos, weight decisions toward self-host friendliness, onboarding simplicity for less-technical users, and AI agents as peers rather than bolt-ons
  *<sub>src: ~/.claude/.../memory/project_paimos.md L30</sub>*
  <!-- rule_ids: project_paimos.md:L30:paimos-decisions-self-host-friendly | cluster: — -->

- 🟡 **STRONG** | `prefer` | Write in telegraph style: noun-phrases ok, minimal grammar, minimal tokens
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L4</sub>*
  <!-- rule_ids: AGENTS.md:L4:telegraph-style | cluster: — -->

- 🟢 SOFT | `do` | Field notes should be precise enough to be implementable as Bosun steps, not just narrative reflection
  *<sub>src: ~/.claude/.../memory/project_fleetcom.md L40</sub>*
  <!-- rule_ids: project_fleetcom.md:L40:field-notes-implementable-as-bosun-steps | cluster: — -->

- 🟢 SOFT | `do` | Greet on session start with hi plus one motivating line
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L18</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L18:greet-on-session-start | cluster: — -->

- 🟢 SOFT | `do` | If user references 'Patrizio,' 'Cici,' or 'pbek,' know who he means without asking
  *<sub>src: ~/.claude/.../memory/reference_patrizio_pbek.md L15</sub>*
  <!-- rule_ids: reference_patrizio_pbek.md:L15:recognize-patrizio-aliases | cluster: — -->

- 🟢 SOFT | `do` | It is encouraged to suggest tools with steep setup curve as long as daily-use payoff is clearly worth it
  *<sub>src: ~/.claude/.../memory/feedback_tool_selection.md L15</sub>*
  <!-- rule_ids: feedback_tool_selection.md:L15:steep-setup-ok-if-payoff | cluster: — -->

- 🟢 SOFT | `do` | Pronounce 'Cici' as 'chi-chi', not 'see-see'
  *<sub>src: ~/.claude/.../memory/reference_patrizio_pbek.md L8</sub>*
  <!-- rule_ids: reference_patrizio_pbek.md:L8:cici-pronunciation | cluster: — -->

- 🟢 SOFT | `do` | Start each session with a hi and one motivating line
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L3</sub>*
  <!-- rule_ids: AGENTS.md:L3:greet-with-motivation | cluster: — -->

- 🟢 SOFT | `do` | When discussing onboarding automation, frame in terms of 'what Bosun will eventually do'
  *<sub>src: ~/.claude/.../memory/project_fleetcom.md L39</sub>*
  <!-- rule_ids: project_fleetcom.md:L39:frame-onboarding-as-bosun | cluster: — -->

- 🟢 SOFT | `prefer` | When suggesting changes to secrets/password mgmt workflow, frame alternatives as 'did you also consider X' rather than 'you should switch to X'
  *<sub>src: ~/.claude/.../memory/reference_patrizio_pbek.md L16</sub>*
  <!-- rule_ids: reference_patrizio_pbek.md:L16:frame-secrets-alternatives-as-questions | cluster: — -->


## Topic: style/file-operations

- 🟡 **STRONG** | `do` | Clone non-markus-barta third-party/OSS repos under ~/Projects/3rdparty
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L19</sub>*
  <!-- rule_ids: AGENTS.md:L19:third-party-projects-dir | cluster: — -->

- 🟡 **STRONG** | `do` | Edit the +agents/ directory only when user explicitly permits
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L49</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L49:agents-dir-permission | cluster: — -->

- 🟡 **STRONG** | `do` | For "use a screenshot" requests, pick newest PNG in ~/Desktop or ~/Downloads
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L29</sub>*
  <!-- rule_ids: AGENTS.md:L29:screenshot-newest-png | cluster: — -->

- 🟡 **STRONG** | `do` | For image optimize, use imageoptim on macOS or image_optim on Linux; STOP and tell user if tool missing
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L32</sub>*
  <!-- rule_ids: AGENTS.md:L32:image-tool-stop-if-missing | cluster: — -->

- 🟡 **STRONG** | `do` | If user says 'use a screenshot': pick newest PNG in ~/Desktop or ~/Downloads, verify by content (ignore filename); size check via sips, optimize via imageoptim
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L180</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L180:screenshot-pick-newest | cluster: — -->

- 🟡 **STRONG** | `do` | Markus's repos live under ~/Code/; if missing, ask to clone https://github.com/markus-barta/<repo>.git
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L37</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L37:repos-under-code | cluster: — -->

- 🟡 **STRONG** | `never` | Never use ~/Code/scratch/ or similar scratch directories
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L39</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L39:no-scratch-dir | cluster: — -->

- 🟡 **STRONG** | `do` | Use `paimos onboard --project INSPR` for current state; treat the local `inspr/playbook.md` as a historical field log
  *<sub>src: PPM/INSPR Knowledge + docs/AGENTS-DOMAIN-DEV.md</sub>*
  <!-- rule_ids: ppm-inspr-onboard-source-of-truth | cluster: — -->

- 🟡 **STRONG** | `do` | Third-party / OSS (non-markus-barta) repos clone under ~/Projects/3rdparty/
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L38</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L38:third-party-under-projects | cluster: — -->

- 🟡 **STRONG** | `do` | Treat ~/Code as the canonical workspace; ask to clone missing repos from github.com/markus-barta/<repo>
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L18</sub>*
  <!-- rule_ids: AGENTS.md:L18:workspace-code-dir | cluster: — -->

- 🟡 **STRONG** | `do` | Verify the screenshot is the right UI by content, ignoring filename
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L30</sub>*
  <!-- rule_ids: AGENTS.md:L30:verify-screenshot-content | cluster: — -->

- 🟡 **STRONG** | `always` | When migrating to Nix, always uninstall the corresponding Homebrew package first to avoid linking errors
  *<sub>src: ~/Code/nixcfg/hosts/mba-imac-work/docs/RUNBOOK.md L287-290</sub>*
  <!-- rule_ids: mba-imac-work-RUNBOOK.md:L289:uninstall-brew-before-nix | cluster: — -->


## Topic: style/markdown-policy

- 🔴 **HARD** | `never` | NEVER create new .md files unless user explicitly requests; prefer editing existing docs (README.md, RUNBOOK.md); ask first when tempted
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L50</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L50:no-new-md-files | cluster: — -->

- 🔴 **HARD** | `never` | Never create new .md files unless user explicitly requests; prefer editing existing
  *<sub>src: ~/Code/inspr/RESUMING-2026-05-12.md L349</sub>*
  <!-- rule_ids: RESUMING-2026-05-12.md:L349:markdown-policy-no-new-files | cluster: — -->

- 🟡 **STRONG** | `never` | No markdown backlog files in nixcfg; backlog management is in PPM
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L176</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L176:no-md-backlog-files-in-nixcfg | cluster: — -->


## Topic: style/naming-conventions

- 🟡 **STRONG** | `always` | In SSH pubkey comments and 1P entry titles, use the FULL local hostname + FULL local username (mba@mbp0), NOT chip codenames (markus@m5)
  *<sub>src: ~/Code/inspr/legacy-rsa-key-inventory.md L222-231</sub>*
  <!-- rule_ids: legacy-rsa-key-inventory.md:L222:full-hostname-username-in-ssh-comments | cluster: — -->

- 🟡 **STRONG** | `dont` | The .cm TLD is intentional, not a typo for .com; do not auto-correct it
  *<sub>src: ~/.claude/.../memory/reference_fleet_endpoints.md L13</sub>*
  <!-- rule_ids: reference_fleet_endpoints.md:L13:cm-tld-intentional | cluster: — -->


## Topic: tools/agenix

- 🔴 **HARD** | `do` | Use agenix -e secrets/<name>.age; never touch .age without permission
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L149</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L149:agenix-edit-cmd | cluster: — -->

- 🟡 **STRONG** | `always` | Declare a secret in secrets/secrets.nix BEFORE running agenix -e on it; agenix errors with attribute missing otherwise
  *<sub>src: ~/.claude/.../memory/project_inspr.md L168</sub>*
  <!-- rule_ids: project_inspr.md:L168:declare-before-edit-agenix | cluster: — -->

- 🟡 **STRONG** | `do` | For cross-island rekeys pass MULTIPLE -i flags (e.g. agenix --rekey -i ~/.ssh/island_a_ed25519 -i ~/.ssh/island_b_ed25519); aborts on first error
  *<sub>src: harvested 2026-05 former-work memory file L52</sub>*
  <!-- rule_ids: former-work-memory.md:L52:agenix-rekey-multi-key | cluster: — -->

- 🟡 **STRONG** | `always` | Recipient additions/removals on existing .age files always require agenix --rekey; without it the change is just metadata and the blob keeps old recipients
  *<sub>src: ~/.claude/.../memory/project_inspr.md L169</sub>*
  <!-- rule_ids: project_inspr.md:L169:rekey-on-recipient-change | cluster: — -->

- 🟡 **STRONG** | `always` | Run agenix CLI from nixcfg root with secrets/<path> relative form because agenix resolves the rules file relative to cwd
  *<sub>src: ~/Code/inspr/playbook.md L405</sub>*
  <!-- rule_ids: playbook.md:L405:agenix-cli-from-nixcfg-root | cluster: — -->

- 🟡 **STRONG** | `prefer` | To install or set up packages on this machine, edit nixcfg and rebuild rather than running brew install or ad-hoc shell commands; confirm with user before going ad-hoc
  *<sub>src: ~/.claude/.../memory/project_nixcfg.md L14</sub>*
  <!-- rule_ids: project_nixcfg.md:L14:edit-nixcfg-not-brew | cluster: — -->

- 🟡 **STRONG** | `do` | Verify rekey expanded recipients by spot-checking decryption with the NEW identity before declaring done; exit code alone can mean kept old recipients
  *<sub>src: ~/.claude/.../memory/project_inspr.md L170</sub>*
  <!-- rule_ids: project_inspr.md:L170:verify-rekey-with-new-identity | cluster: — -->

- 🟡 **STRONG** | `do` | When troubleshooting environment issues, check whether the tool is declared in nixcfg before assuming it should be installed imperatively
  *<sub>src: ~/.claude/.../memory/project_nixcfg.md L15</sub>*
  <!-- rule_ids: project_nixcfg.md:L15:check-nixcfg-before-imperative | cluster: — -->

- 🟢 SOFT | `prefer` | Run agenix --rekey from cd ./secrets to load only the bare-rules secrets/secrets.nix, avoiding 18× duplicate iteration noise from dual-name re-export wrappers
  *<sub>src: ~/Code/inspr/playbook.md L472</sub>*
  <!-- rule_ids: playbook.md:L472:cd-secrets-for-rekey-clean | cluster: — -->


## Topic: tools/bootstrap-scripts

- 🟡 **STRONG** | `always` | In Zitadel curl-handler case blocks, accept 400 + 'No changes' body as idempotent-success signal (Zitadel uses 400 instead of 409 for no-op PUT)
  *<sub>src: ~/Code/inspr/playbook.md L694</sub>*
  <!-- rule_ids: playbook.md:L694:zitadel-400-no-changes-is-success | cluster: — -->

- 🟡 **STRONG** | `always` | Self-hosted Zitadel ships THREE first-init traps (machinekey EACCES, complexity policy uppercase requirement, Console missing REFRESH_TOKEN grant) — bake all three into bootstrap
  *<sub>src: ~/Code/inspr/playbook.md L688</sub>*
  <!-- rule_ids: playbook.md:L688:bake-traps-into-bootstrap-script | cluster: — -->


## Topic: tools/gh

- 🟡 **STRONG** | `never` | Use gh pr view/diff; never paste GitHub URLs
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L107</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L107:gh-not-paste-urls | cluster: — -->


## Topic: tools/ssh

- 🟡 **STRONG** | `do` | A new machine joining the fleet must be enrolled in Headscale (preauth key, ACL/tag assignment) before it can reach anything
  *<sub>src: ~/.claude/.../memory/reference_network_tailscale_headscale.md L13</sub>*
  <!-- rule_ids: reference_network_tailscale_headscale.md:L13:headscale-enrollment-required | cluster: — -->

- 🔴 **HARD** | `do` | When LAN access does not work, reach hosts over the tailnet **by IP** — `tailscale status` to read it, then `ssh mba@100.64.x.y` (cloud keeps `-p 2222`). 🔴 **Never** `*.ts.barta.cm`: MagicDNS is OFF by Markus's permanent decision (it was breaking agent/API sessions) and those names resolve to nothing. See `AGENTS-DOMAIN-OPS.md` § MagicDNS.
  *<sub>src: ~/Code/nixcfg/docs/INFRASTRUCTURE.md L190 — corrected 2026-08-07 (INSPR-283 / OPS-146)</sub>*
  <!-- rule_ids: INFRASTRUCTURE.md:L190:always-use-tailscale-when-lan-fails | cluster: — -->

- 🟡 **STRONG** | `do` | Cloud servers: ssh mba@cs<n>.barta.cm -p 2222 (csb0, csb1)
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L143</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L143:ssh-cloud-port-2222 | cluster: — -->

- 🟡 **STRONG** | `do` | Home LAN hosts: ssh mba@<host>.lan (hsb0, hsb1, hsb8, gpc0)
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L142</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L142:ssh-home-lan-mba | cluster: — -->

- 🟡 **STRONG** | `do` | On macOS use the Tailscale .app CLI (/Applications/Tailscale.app/Contents/MacOS/Tailscale), NOT brew tailscale
  *<sub>src: ~/Code/nixcfg/docs/INFRASTRUCTURE.md L222-224</sub>*
  <!-- rule_ids: INFRASTRUCTURE.md:L222:macos-tailscale-use-app-cli | cluster: — -->

- 🟡 **STRONG** | `do` | On reverse-proxy fleets, distinguish host hostname (for SSH/admin) from service hostname (for clients); always ask which is needed
  *<sub>src: ~/.claude/.../memory/reference_fleet_endpoints.md L15-19</sub>*
  <!-- rule_ids: reference_fleet_endpoints.md:L19:disambiguate-host-vs-service | cluster: — -->

- 🟡 **STRONG** | `do` | Reach internal hosts through the tailnet, not VPN concentrators, port-forwarding, public IP exposure, or SSH bastions
  *<sub>src: ~/.claude/.../memory/reference_network_tailscale_headscale.md L12</sub>*
  <!-- rule_ids: reference_network_tailscale_headscale.md:L12:tailnet-only-access | cluster: — -->

- 🟡 **STRONG** | `do` | Use https://hs.barta.cm as the canonical Tailscale --login-server value, never the container host hostname cs0.barta.cm
  *<sub>src: ~/.claude/.../memory/reference_fleet_endpoints.md L10</sub>*
  <!-- rule_ids: reference_fleet_endpoints.md:L10:headscale-service-url | cluster: — -->

- 🟢 SOFT | `do` | Confirm with user before assuming Tailscale SSH is enabled vs classic SSH keys
  *<sub>src: ~/.claude/.../memory/reference_network_tailscale_headscale.md L15</sub>*
  <!-- rule_ids: reference_network_tailscale_headscale.md:L15:confirm-tailscale-ssh | cluster: — -->


## Topic: tools/zellij

- 🟡 **STRONG** | `do` | Terminal multiplexer is zellij, NOT tmux; layouts in ~/.config/zellij/
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L152</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L152:zellij-not-tmux | cluster: — -->

- 🟡 **STRONG** | `do` | Use zellij as the terminal multiplexer (not tmux)
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L240-241</sub>*
  <!-- rule_ids: AGENTS.md:L240:zellij-not-tmux | cluster: — -->


## Topic: process/build-test

- 🟡 **STRONG** | `do` | Before handoff: full gate of lint, typecheck, tests, docs
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L125</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L125:full-gate-before-handoff | cluster: — -->


## Topic: process/critical-thinking

- 🟡 **STRONG** | `prefer` | Source preference for web research: 2026+ first, fallback 2025+, then older
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L116</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L116:source-preference-recent-first | cluster: — -->

- 🟢 SOFT | `do` | Search the web early when researching
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L114</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L114:web-search-early | cluster: — -->


## Topic: process/design-doctrine

- 🔴 **HARD** | `always` | Use substrate-portable primitives first (universal across forges); forge-specific richness as opt-in extras only — locking core abstraction to one vendor betrays portability doctrine
  *<sub>src: ~/Code/inspr/proposals/git-atelier-credentials.md L37</sub>*
  <!-- rule_ids: proposals/git-atelier-credentials.md:L37:substrate-portable-primitives-first | cluster: — -->

- 🟡 **STRONG** | `avoid` | GitHub Apps documented as tier-4 opt-in only; richness justifies vendor lock-in only with permanent GitHub commitment AND need for App-specific features
  *<sub>src: ~/Code/inspr/proposals/git-atelier-credentials.md L179</sub>*
  <!-- rule_ids: proposals/git-atelier-credentials.md:L179:github-apps-tier-4-opt-in-only | cluster: — -->

- 🟡 **STRONG** | `prefer` | Good primitives expose ONE shape for orthogonal use cases (servers vs workstations); test: can both shapes coexist on the same atelier? If different modules needed, abstraction is wrong
  *<sub>src: ~/Code/inspr/playbook.md L901</sub>*
  <!-- rule_ids: playbook.md:L901:server-vs-workstation-identity-distinction | cluster: — -->

- 🟡 **STRONG** | `avoid` | Manual rotation at any cadence ≤ 1 year is operational hell at scale; prefer credential primitives that never rotate or auto-rotate invisibly
  *<sub>src: ~/Code/inspr/proposals/git-atelier-credentials.md L165-168</sub>*
  <!-- rule_ids: proposals/git-atelier-credentials.md:L165:never-manual-rotation-at-scale | cluster: — -->

- 🟡 **STRONG** | `always` | When designing INSPR primitives, the test isn't 'does it work on the current forge' — it's 'does it survive substrate migration with config-level changes only'
  *<sub>src: ~/Code/inspr/playbook.md L798</sub>*
  <!-- rule_ids: playbook.md:L798:substrate-portability-test | cluster: — -->


## Topic: process/licensing


## Topic: process/lockout-recovery

- 🟡 **STRONG** | `always` | Keep PasswordAuthentication=true on csb0/csb1 until per-host ed25519 keys are deployed AND validated AND legacy RSA is fully retired (defence-in-depth)
  *<sub>src: ~/Code/inspr/legacy-rsa-key-inventory.md L180-182</sub>*
  <!-- rule_ids: legacy-rsa-key-inventory.md:L182:keep-passwordauth-true-during-retirement | cluster: — -->


## Topic: workflow/agent-handoff

- 🟡 **STRONG** | `prefer` | In multi-session agent workstreams, when waiting for the other session, write a self-contained ticket (code/diffs/validation gates/rollback) and hand off rather than turn-taking
  *<sub>src: ~/Code/inspr/playbook.md L964</sub>*
  <!-- rule_ids: playbook.md:L964:codify-and-handoff-beats-turn-taking | cluster: — -->

- 🟡 **STRONG** | `prefer` | Multi-session coordination: codify-and-hand-off beats turn-taking — one agent writes self-contained ticket with code/diffs/gates/rollback, hands off to other for batch execution
  *<sub>src: ~/Code/inspr/RESUMING-2026-05-13.md L49</sub>*
  <!-- rule_ids: RESUMING-2026-05-13.md:L49:codify-and-handoff-multi-session | cluster: — -->

- 🟡 **STRONG** | `do` | Query Pharos (pharos.barta.cm) as the canonical live source for fleet inventory; never assume static lists (FleetCom retired — superseded by Pharos)
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L20</sub>*
  <!-- rule_ids: AGENTS.md:L20:fleetcom-canonical-inventory | cluster: — -->

- 🟡 **STRONG** | `do` | Unrecognized changes: assume other agent, keep going, focus your changes; if it causes issues, stop and ask
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L135</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L135:assume-other-agent-on-unrecognized | cluster: — -->


## Topic: workflow/ppm

- 🔴 **HARD** | `never` | For raw curl PPM auth: source ~/.inspr/secrets/agents/PPMAPIKEY.env (INSPR-164 canonical path) which exposes $PPMAPIKEY; never cat/read the env file. INSPR workstation policy uses interactive `paimos auth login` through the OS keyring; approved encrypted storage may inject runtime-only headless credentials — see /ppm.
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L170 · path migrated 2026-05-13 (INSPR-164) · CLI vs curl distinction clarified 2026-05-16 (INSPR-193)</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L170:ppm-source-env | cluster: — -->

- 🟡 **STRONG** | `always` | Always GET a PPM ticket's current state BEFORE any PUT — PPM PUT replaces the record wholesale, so capture the full restore-state first and verify ticket identity (id + title) before mutating.
  *<sub>src: ~/Code/inspr/playbook.md L631 · ~/.claude/.../memory/project_inspr.md L148 · incident: PAI-313 contamination 2026-05-10 · synthesized 2026-05-14 (Phase 4 broadening)</sub>*
  <!-- rule_ids: playbook.md:L631:get-history-before-ppm-put,project_inspr.md:L148:get-history-before-put | cluster: workflow-ppm-015 -->

- 🟡 **STRONG** | `do` | Before creating a PPM issue search to dedupe via GET /api/search?q=<topic>
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L252 · ~/.claude/.../memory/feedback_agent_protocol.md L174</sub>*
  <!-- rule_ids: AGENTS.md:L252:search-before-create-ppm,feedback_agent_protocol.md:L174:ppm-search-before-create | cluster: workflow-ppm-017 -->

- 🟡 **STRONG** | `do` | For POST /api/projects/<id>/issues, project_id goes in the URL, not the body; passing it in body returns an error
  *<sub>src: ~/.claude/.../memory/reference_paimos_api_access.md L37</sub>*
  <!-- rule_ids: reference_paimos_api_access.md:L37:project-id-in-url-not-body | cluster: — -->

- 🟡 **STRONG** | `do` | PUT /api/issues/<id> REPLACES fields wholesale; PATCH is silently ignored (no error, no effect)
  *<sub>src: ~/.claude/.../memory/project_inspr.md L149</sub>*
  <!-- rule_ids: project_inspr.md:L149:put-replaces-wholesale | cluster: — -->

- 🟡 **STRONG** | `do` | When PPM writes are explicitly authorized, start the PPM timer when beginning work and stop it when done; mba is user_id 2.
  *<sub>src: ~/Code/fleetcom/AGENTS.md L42</sub>*
  <!-- rule_ids: AGENTS.md:L42:ppm-time-tracking | cluster: — -->

- 🟡 **STRONG** | `prefer` | Sweep tickets need explicit time-boxing at the per-item level — promote items past 30 min to their own focused tickets; promoting is a feature, not a failure
  *<sub>src: ~/Code/inspr/playbook.md L767</sub>*
  <!-- rule_ids: playbook.md:L767:sweep-tickets-time-box-per-item | cluster: — -->

- 🟡 **STRONG** | `do` | Treat Paimos APIs as read-only by default; do not create, update, or delete unless explicitly asked
  *<sub>src: ~/.claude/.../memory/reference_paimos_api_access.md L94</sub>*
  <!-- rule_ids: reference_paimos_api_access.md:L94:ppm-read-only-default | cluster: — -->

- 🟡 **STRONG** | `always` | Use POST /api/projects/{id}/issues for project-scoped issue creation; POST /api/issues with project_id returns 'only sprint issues may be created without a project'
  *<sub>src: ~/Code/inspr/playbook.md L567</sub>*
  <!-- rule_ids: playbook.md:L567:ppm-post-issues-uses-nested-form | cluster: — -->

- 🟡 **STRONG** | `always` | Use PUT /api/issues/{id} for updates; PATCH is silently ignored by PPM
  *<sub>src: ~/Code/inspr/playbook.md L567</sub>*
  <!-- rule_ids: playbook.md:L567:ppm-use-put-not-patch | cluster: — -->

- 🟡 **STRONG** | `do` | Use nested /api/projects/<id>/issues for per-project queries; the project_id query param on /api/issues is not honored as a filter
  *<sub>src: ~/.claude/.../memory/reference_paimos_api_access.md L36</sub>*
  <!-- rule_ids: reference_paimos_api_access.md:L36:per-project-issues-endpoint | cluster: — -->

- 🟢 SOFT | `do` | Stay at project-level for unfamiliar projects; do not browse individual issues unless asked
  *<sub>src: ~/.claude/.../memory/reference_paimos_api_access.md L95</sub>*
  <!-- rule_ids: reference_paimos_api_access.md:L95:project-level-default-scope | cluster: — -->


## Topic: pacing/interactive

- 🔴 **HARD** | `always` | During interactive procedures (UI clicks, keyboard commands, rotation/migration steps) drive ONE step at a time and wait for explicit done before showing the next step
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L22 · incident: 2026-05-13 quote</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L22:one-step-at-a-time | cluster: — -->

- 🔴 **HARD** | `never` | Never dump a 5-step or 10-step playbook in one message expecting the user to crawl through it
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L24 · incident: 2026-05-13 quote</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L24:no-multi-step-dump | cluster: — -->

- 🔴 **HARD** | `never` | Never write an 8-item checklist expecting parallel execution by a human
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L25</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L25:no-parallel-checklists | cluster: — -->

- 🟡 **STRONG** | `do` | Keep a private todo list of remaining steps so you don't lose track, but only show the user the current step
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L28</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L28:keep-private-todo-list | cluster: — -->


## Topic: pacing/long-running

- 🟡 **STRONG** | `do` | Prefix commands >10s with `date &&` (bash) or `date; and` (fish) so timing is observable; applies to nix builds, docker ops, large file ops, test suites, package installs
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L121</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L121:date-prefix-long-commands | cluster: — -->

- 🟢 SOFT | `prefer` | Long-running commands should be prefixed with 'date &&'; use run_in_background for >30s nix builds / docker pulls
  *<sub>src: ~/Code/inspr/RESUMING-2026-05-12.md L351</sub>*
  <!-- rule_ids: RESUMING-2026-05-12.md:L351:long-running-prefix-with-date | cluster: — -->


## Topic: git/auth

- 🟡 **STRONG** | `always` | Declare git credential helper via Home Manager programs.git.settings.credential rather than using gh auth setup-git, which collides with HM-managed read-only ~/.config/git/config
  *<sub>src: ~/Code/inspr/playbook.md L409-417</sub>*
  <!-- rule_ids: playbook.md:L409:declare-credential-helper-via-HM | cluster: — -->

- 🟡 **STRONG** | `always` | For multi-org git workflow, always use the alias form git@github-<org>:<org>/<repo>.git for pushes; never the bare git@github.com: form
  *<sub>src: ~/Code/inspr/playbook.md L489</sub>*
  <!-- rule_ids: playbook.md:L489:always-use-ssh-alias-form | cluster: — -->


## Topic: git/identity

- 🔴 **HARD** | `always` | For developer/user identity use exact values: name 'Markus Barta', email 'markus@barta.com', GitHub handle 'markus-barta'
  *<sub>src: ~/.claude/.../memory/user_identity.md L9-11</sub>*
  <!-- rule_ids: user_identity.md:L9:canonical-identity-name | cluster: — -->

- 🟡 **STRONG** | `prefer` | For PAT identity: if the entity makes decisions while no human is actively present give it its own GitHub account; otherwise the human's account is fine
  *<sub>src: ~/Code/inspr/playbook.md L430</sub>*
  <!-- rule_ids: playbook.md:L430:pat-identity-mapping-rule | cluster: — -->

- 🟡 **STRONG** | `prefer` | Identity/developer config should live declaratively in nixcfg; setting git config --global or anything fleet-wide imperatively should be confirmed first
  *<sub>src: ~/.claude/.../memory/user_identity.md L16</sub>*
  <!-- rule_ids: user_identity.md:L16:identity-declarative-in-nixcfg | cluster: — -->

- 🟡 **STRONG** | `do` | Use markus@barta.com (personal) for all git identity across ~/Code
  *<sub>src: ~/Code/nixcfg/hosts/imac0/docs/RUNBOOK.md L85-89</sub>*
  <!-- rule_ids: imac0-RUNBOOK.md:L85:nixcfg-uses-personal-git-identity | cluster: — -->

- 🟡 **STRONG** | `always` | On migration from manual to HM-managed git config, rename legacy ~/.gitconfig (don't delete) — it silently shadows ~/.config/git/config and wins precedence
  *<sub>src: ~/Code/inspr/playbook.md L442</sub>*
  <!-- rule_ids: playbook.md:L442:legacy-gitconfig-shadows-xdg | cluster: — -->

- 🟡 **STRONG** | `prefer` | Use per-repo git config (no --global flag) on bootstrap; declare fleet-wide identity in nixcfg as the canonical source
  *<sub>src: ~/Code/inspr/playbook.md L60-68</sub>*
  <!-- rule_ids: playbook.md:L66:per-repo-git-config-bootstrap | cluster: — -->


## Topic: git/safety

- 🔴 **HARD** | `never` | Destructive git ops (reset --hard, clean, restore, rm) forbidden unless explicit
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L58</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L58:destructive-git-forbidden | cluster: — -->

- 🟡 **STRONG** | `dont` | Don't delete or rename unexpected stuff; stop and ask
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L59</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L59:dont-delete-rename-unexpected | cluster: — -->

- 🟡 **STRONG** | `prefer` | In multi-agent repos with unstaged dirt that isn't yours, stash-by-path the not-yours (git stash push -- <paths>), then pull/push/pop — don't git stash everything
  *<sub>src: ~/Code/inspr/playbook.md L771</sub>*
  <!-- rule_ids: playbook.md:L771:stash-by-path-for-multi-agent-repos | cluster: — -->

- 🟡 **STRONG** | `always` | In nixcfg + inspr-at: when commit appears to silently abort + push says 'Everything up-to-date', check git status for MM state — pre-commit linter ate the staged diff
  *<sub>src: ~/Code/inspr/RESUMING-2026-05-12.md L350</sub>*
  <!-- rule_ids: RESUMING-2026-05-12.md:L350:check-MM-on-silent-push | cluster: — -->

- 🟡 **STRONG** | `never` | No git commit --amend unless asked
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L61</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L61:no-amend-unless-asked | cluster: — -->

- 🟡 **STRONG** | `do` | Push is part of the normal flow when working on agreed changes; do it without asking
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L84 · ~/.claude/.../memory/feedback_agent_protocol.md L55</sub>*
  <!-- rule_ids: AGENTS.md:L84:push-without-asking-on-agreed-changes,feedback_agent_protocol.md:L55:push-without-asking | cluster: git-safety-005 -->

- 🟡 **STRONG** | `always` | When git push reports nothing pushed despite a fresh commit attempt, check git status for MM (staged + modified-since-stage) — pre-commit linter ate the staged diff
  *<sub>src: ~/Code/inspr/playbook.md L629</sub>*
  <!-- rule_ids: playbook.md:L629:check-MM-state-on-silent-push | cluster: — -->


## Topic: nix/modules

- 🟡 **STRONG** | `prefer` | For atelier mirrors, prefer verbatim copy with header note pointing at source until divergence is real; only extract to inspr-modules with ≥2 consumers AND confirmed divergence pressure
  *<sub>src: ~/Code/inspr/playbook.md L786</sub>*
  <!-- rule_ids: playbook.md:L786:atelier-mirror-until-divergence | cluster: — -->

- 🟡 **STRONG** | `prefer` | The bar for 'common' should be 'every host MUST have this for INSPR to function correctly,' NOT 'every host I've inventoried happens to have this'
  *<sub>src: ~/Code/inspr/playbook.md L637</sub>*
  <!-- rule_ids: playbook.md:L637:strict-baseline-bar-for-common | cluster: — -->

- 🟡 **STRONG** | `prefer` | When modules might be tested via harnesses with permissive stub typing, avoid lib.mkMerge in favor of direct lib.listToAttrs construction for testability
  *<sub>src: ~/Code/inspr/playbook.md L844</sub>*
  <!-- rule_ids: playbook.md:L844:avoid-mkMerge-with-permissive-stub-typing | cluster: — -->

- 🟢 SOFT | `prefer` | For new modules, ship module + tests + README in the same PR/commit so reviewers can verify the full contract in one diff
  *<sub>src: ~/Code/inspr/playbook.md L848</sub>*
  <!-- rule_ids: playbook.md:L848:bundle-module-test-readme-in-one-pr | cluster: — -->


## Topic: nixos/activation

- 🟡 **STRONG** | `prefer` | Activation steps that set umask (e.g. inspr.secrets.agents) should restore prior umask before exiting to avoid externalized side effects on subsequent activation steps
  *<sub>src: ~/Code/inspr/playbook.md L1102 · incident: Day-11</sub>*
  <!-- rule_ids: playbook.md:L1102:restore-umask-after-side-effect | cluster: — -->


## Topic: nixos/build-safety

- 🔴 **HARD** | `never` | NEVER build NixOS configs on macOS; from macOS build remotely via ssh; macOS Home Manager configs CAN be built locally
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L97-103</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L97:never-build-nixos-on-macos | cluster: — -->


## Topic: nixos/host-template

- 🟡 **STRONG** | `dont` | Do not conflate hosts/mba-mbp-work (old Intel) with hosts/mbp0 (new M5); they are different physical hardware and configs
  *<sub>src: ~/.claude/.../memory/project_machine_mbp_provenance.md L18-20</sub>*
  <!-- rule_ids: project_machine_mbp_provenance.md:L20:dont-conflate-host-configs | cluster: — -->

- 🟡 **STRONG** | `dont` | Per-host divergence is expected; don't assume something on one machine exists on another without checking the host's nix config
  *<sub>src: ~/.claude/.../memory/project_nixcfg.md L16</sub>*
  <!-- rule_ids: project_nixcfg.md:L16:per-host-divergence-expected | cluster: — -->


## Topic: infra/fleet-state


## Topic: infra/tailscale

- 🟢 SOFT | `prefer` | For Headscale on macOS, prefer the Tailscale.app standalone variant (brew cask tailscale-app), not the App Store sandboxed version
  *<sub>src: ~/Code/inspr/playbook.md L379</sub>*
  <!-- rule_ids: playbook.md:L379:use-tailscale-app-standalone-cask | cluster: — -->
