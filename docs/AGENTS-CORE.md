# AGENTS — Core

*Layer: `universal` · Synthesized 2026-05-14 by INSPR-179 Phase 4 · This layer holds 199 rules. (Post-Phase-6: this file is no longer auto-loaded; it remains as exhaustive reference. Slash commands `/dev /ops /secrets /nix /ppm /style /incident` load topic-relevant domain packs on demand.)*

This document is the authoritative source for rules every Claude agent in Markus Barta's fleet follows, regardless of role, repo, or profile. Other layers (read top-down for full context):

- **[AGENTS-CORE.md](./AGENTS-CORE.md)** — universal rules every agent follows
- **[AGENTS-PROFILE-MARKUS.md](./AGENTS-PROFILE-MARKUS.md)** — Markus Barta's personal preferences
- **AGENTS-AGENT-*.md** — per-role overlays (one per agent identity)
- **per-repo AGENTS.md** in nixcfg/fleetcom/inspr — repo-specific deltas

---

## Topic: security/design

- 🟡 **STRONG** | `prefer` | When an app has too much privilege via its credential, prefer to constrain the credential at env boundary rather than add defensive checks in app code
  *<sub>src: ~/Code/inspr/playbook.md L747</sub>*
  <!-- rule_ids: playbook.md:L747:constrain-at-credential-boundary | cluster: — -->


## Topic: security/destructive-ops

- 🔴 **HARD** | `always` | Agent ships reversible changes without asking; pauses and explicitly asks before destructive ops (--rekey, nixos-rebuild switch on critical services, secret material)
  *<sub>src: ~/Code/inspr/playbook.md L493</sub>*
  <!-- rule_ids: playbook.md:L493:agent-pause-before-destructive-ops | cluster: — -->

- 🔴 **HARD** | `never` | Destructive git ops (reset --hard, clean, restore, rm) forbidden unless explicitly permitted
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L87</sub>*
  <!-- rule_ids: AGENTS.md:L87:destructive-git-ops-forbidden | cluster: — -->

- 🔴 **HARD** | `never` | Do not delete or rename unexpected items; stop and ask
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L88</sub>*
  <!-- rule_ids: AGENTS.md:L88:dont-delete-rename-unexpected | cluster: — -->

- 🟡 **STRONG** | `always` | For any infra change touching auth, keep a live root/sudo session open as a recovery channel throughout the change — use it only for recovery, not for the change
  *<sub>src: ~/Code/inspr/playbook.md L522</sub>*
  <!-- rule_ids: playbook.md:L522:keep-live-recovery-session | cluster: — -->


## Topic: security/encrypted-files

- 🔴 **HARD** | `never` | Never touch .age or .env files without explicit permission
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L171 · ~/Code/nixcfg/+agents/rules/SYSOP.md L195 · ~/Code/nixcfg/+agents/rules/SYSOP-GB.md L131 · ~/.claude/.../memory/feedback_agent_protocol.md L85</sub>*
  <!-- rule_ids: AGENTS.md:L171:never-touch-encrypted-files,SYSOP.md:L195:no-touch-age-or-env,SYSOP-GB.md:L131:no-touching-age-or-env-without-permission,feedback_agent_protocol.md:L85:no-encrypted-files-without-permission | cluster: security-encrypted-files-001 -->

- 🔴 **HARD** | `do` | Provide commands for the user to run themselves (e.g. agenix -e secrets/<name>.age) — do not run them
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L176</sub>*
  <!-- rule_ids: AGENTS.md:L176:guide-user-to-run-agenix | cluster: — -->

- 🔴 **HARD** | `always` | To modify encrypted content: ASK ('I'll need to decrypt. Should I proceed?'), GUIDE (provide commands for user to run), VERIFY (file size before/after), NEVER assume permission
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L87-91</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L87:encrypted-file-modification-flow | cluster: — -->

- 🔴 **HARD** | `always` | When user wants to modify encrypted content, ask permission before decrypting
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L175</sub>*
  <!-- rule_ids: AGENTS.md:L175:ask-before-decrypting | cluster: — -->

- 🟡 **STRONG** | `do` | Check encrypted file size before/after edit (encrypted file is typically 5KB+)
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L177</sub>*
  <!-- rule_ids: AGENTS.md:L177:verify-encrypted-file-size | cluster: — -->


## Topic: security/git-commits

- 🔴 **HARD** | `always` | AI duty: detect potential secret -> STOP -> alert user -> suggest env var -> wait for confirmation
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L107 · ~/.claude/.../memory/feedback_agent_protocol.md L70</sub>*
  <!-- rule_ids: AGENTS.md:L107:detect-secret-stop-suggest-envvar,feedback_agent_protocol.md:L70:detect-secret-stop-alert | cluster: security-git-commits-004 -->

- 🔴 **HARD** | `always` | Always scan git diff for secrets before committing.
  *<sub>src: ~/Code/fleetcom/.claude/commands/dev.md L30</sub>*
  <!-- rule_ids: dev.md:L30:scan-diff-for-secrets | cluster: — -->

- 🔴 **HARD** | `always` | Before every commit: git diff to scan for secrets, git status to verify files
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L103 · ~/.claude/.../memory/feedback_agent_protocol.md L68</sub>*
  <!-- rule_ids: AGENTS.md:L103:git-diff-before-every-commit,feedback_agent_protocol.md:L68:scan-diff-before-commit | cluster: security-git-commits-003 -->

- 🔴 **HARD** | `never` | Never commit secrets: plain text passwords, API keys, tokens, bcrypt hashes, .env files with real credentials
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L96-99 · ~/.claude/.../memory/feedback_agent_protocol.md L66</sub>*
  <!-- rule_ids: AGENTS.md:L96:never-commit-secrets,feedback_agent_protocol.md:L66:never-commit-secrets | cluster: security-git-commits-002 -->


## Topic: security/secrets-output

- 🔴 **HARD** | `always` | Any script that prints secrets to stdout MUST default to redacted (e.g. <redacted, length=N>); cleartext via opt-in only (e.g. --print-secret)
  *<sub>src: ~/Code/inspr/playbook.md L692</sub>*
  <!-- rule_ids: playbook.md:L692:scripts-default-redacted-output | cluster: — -->

- 🔴 **HARD** | `always` | Apply the principle (any command whose output IS the resolved environment is forbidden), not the literal list — list will never be exhaustive
  *<sub>src: ~/Code/inspr/playbook.md L1034 · incident: Day-11</sub>*
  <!-- rule_ids: playbook.md:L1034:apply-principle-not-list-for-secret-output | cluster: — -->

- 🔴 **HARD** | `avoid` | Avoid any command where secret values could appear in stdout or stderr.
  *<sub>src: ~/Code/fleetcom/AGENTS.md L422</sub>*
  <!-- rule_ids: AGENTS.md:L422:no-secrets-in-output-streams | cluster: — -->

- 🔴 **HARD** | `always` | Before EVERY Bash command, mentally check: could stdout/stderr contain secrets? does it touch ~/.inspr/secrets/, ~/.ssh/, /run/agenix/, *.env, *.age? does it involve env/printenv/set/export/declare/direnv export/source/cat/head/tail?
  *<sub>src: ~/Code/inspr/playbook.md L1042-1046 · incident: Day-11</sub>*
  <!-- rule_ids: playbook.md:L1042:pre-flight-checklist-before-bash | cluster: — -->

- 🔴 **HARD** | `do` | Before every Bash command, ask: could this command stdout/stderr contain a secret value?
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L149</sub>*
  <!-- rule_ids: AGENTS.md:L149:preflight-could-stdout-leak | cluster: — -->

- 🔴 **HARD** | `do` | Before every Bash command, check whether it touches ~/Secrets/, ~/.inspr/secrets/, ~/.ssh/<not-pub>, /run/agenix/, .env, .age or .gpg paths
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L150-151</sub>*
  <!-- rule_ids: AGENTS.md:L150:preflight-touches-secret-paths | cluster: — -->

- 🔴 **HARD** | `always` | Bootstrap scripts that write secrets to .env MUST default to <redacted, length=N> in stdout; cleartext via opt-in only (e.g. --print-secret)
  *<sub>src: ~/Code/inspr/RESUMING-2026-05-12.md L230</sub>*
  <!-- rule_ids: RESUMING-2026-05-12.md:L230:bootstrap-redact-by-default | cluster: — -->

- 🔴 **HARD** | `never` | Do not assume 'just this once is fine' for secret exposure; there is no fine
  *<sub>src: ~/.claude/.../memory/reference_secrets_local_env_pattern.md L26</sub>*
  <!-- rule_ids: reference_secrets_local_env_pattern.md:L26:no-just-this-once | cluster: — -->

- 🔴 **HARD** | `never` | Do not copy the secret file to a different location to 'stage' it for use
  *<sub>src: ~/.claude/.../memory/reference_secrets_local_env_pattern.md L27</sub>*
  <!-- rule_ids: reference_secrets_local_env_pattern.md:L27:no-staging-copy | cluster: — -->

- 🔴 **HARD** | `never` | Do not decrypt-and-display, base64-decode-and-display, or otherwise transform-then-display secret values
  *<sub>src: ~/.claude/.../memory/reference_secrets_local_env_pattern.md L28</sub>*
  <!-- rule_ids: reference_secrets_local_env_pattern.md:L28:no-decrypt-and-display | cluster: — -->

- 🔴 **HARD** | `never` | Do not remove a filter from a command that returned empty and re-run unfiltered; diagnose the underlying state instead
  *<sub>src: ~/.claude/.../memory/reference_secrets_local_env_pattern.md L30</sub>*
  <!-- rule_ids: reference_secrets_local_env_pattern.md:L30:no-filter-removal | cluster: — -->

- 🔴 **HARD** | `never` | Do not run commands whose output is the resolved environment (direnv export, set, declare -x, declare -p, compgen -e, export -p, docker exec cat env, kubectl get secret -o yaml)
  *<sub>src: ~/.claude/.../memory/reference_secrets_local_env_pattern.md L29 · incident: playbook.md Day-11 (2026-05-13, 6 prod credentials leaked)</sub>*
  <!-- rule_ids: reference_secrets_local_env_pattern.md:L29:no-env-resolving-commands | cluster: — -->

- 🔴 **HARD** | `always` | For secret-pipeline verification, use only safe primitives: ls|wc -l (count), [ -n $VAR ] && echo set (presence), error-count grep, file (content sniff) — never echo $VAR
  *<sub>src: ~/Code/inspr/playbook.md L1036-1041 · incident: Day-11</sub>*
  <!-- rule_ids: playbook.md:L1036:safe-verification-primitives-only | cluster: — -->

- 🔴 **HARD** | `never` | If a filtered command returns empty unexpectedly, do NOT remove the filter and re-run — diagnose the underlying state; the filter was probably correct
  *<sub>src: ~/Code/inspr/playbook.md L1046 · incident: Day-11 · ~/Code/nixcfg/+agents/rules/AGENTS.md L154</sub>*
  <!-- rule_ids: playbook.md:L1046:filter-empty-do-not-remove-filter,AGENTS.md:L154:dont-remove-filter-on-empty | cluster: security-secrets-output-017 -->

- 🔴 **HARD** | `never` | NEVER use sed/head/cat on files in ~/Secrets/ even with truncation intent — partial-key leaks slip through
  *<sub>src: ~/Code/inspr/RESUMING-2026-05-12.md L228</sub>*
  <!-- rule_ids: RESUMING-2026-05-12.md:L228:never-sed-head-cat-on-secrets | cluster: — -->

- 🔴 **HARD** | `never` | Never apply text manipulation (sed/head/cat/cut) to anything in ~/Secrets/ — partial-key leaks slip through (e.g. sed-truncating leaked partial PPM API key)
  *<sub>src: ~/Code/inspr/playbook.md L692</sub>*
  <!-- rule_ids: playbook.md:L692:never-text-manipulation-on-secrets | cluster: — -->

- 🔴 **HARD** | `never` | Never cat, head, tail, less, more, bat, xxd, od, or any other tool that prints contents of files in /Users/mba/.inspr/secrets/agents/
  *<sub>src: ~/.claude/.../memory/reference_secrets_local_env_pattern.md L22 · incident: playbook.md Day-11</sub>*
  <!-- rule_ids: reference_secrets_local_env_pattern.md:L22:no-cat-on-secret-files | cluster: — -->

- 🔴 **HARD** | `never` | Never dump container or process environment unfiltered — avoid `docker inspect`, `ps auxe`, and `kubectl describe`/`env`-style commands that may expand secrets in their output; if env inspection is required, filter to keys-only or scrub values first. Canonical incident: re-send-from-PPM leak.
  *<sub>src: ~/Code/inspr/playbook.md L692 · ~/Code/inspr/RESUMING-2026-05-12.md L229 · ~/.claude/.../memory/project_inspr.md L235 · incident: 2026-05-11 leak · synthesized 2026-05-14 (Phase 4 broadening)</sub>*
  <!-- rule_ids: playbook.md:L692:never-grep-container-env-unfiltered,RESUMING-2026-05-12.md:L229:never-docker-inspect-config-env-unfiltered,project_inspr.md:L235:no-docker-inspect-env-unfiltered | cluster: security-secrets-output-011 -->

- 🔴 **HARD** | `never` | Never include the secret value in any tool output, chat message, commit, log, or file the user might later open
  *<sub>src: ~/.claude/.../memory/reference_secrets_local_env_pattern.md L24</sub>*
  <!-- rule_ids: reference_secrets_local_env_pattern.md:L24:no-secret-in-tool-output | cluster: — -->

- 🔴 **HARD** | `never` | Never pass the secret value as a literal command-line argument (visible in ps, shell history, audit logs)
  *<sub>src: ~/.claude/.../memory/reference_secrets_local_env_pattern.md L25</sub>*
  <!-- rule_ids: reference_secrets_local_env_pattern.md:L25:no-secret-as-cli-arg | cluster: — -->

- 🔴 **HARD** | `never` | Never pipe a secret-bearing file into a downstream-visible position (e.g. source <env-file>; env, agenix -d <file>.age to stdout)
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L134</sub>*
  <!-- rule_ids: AGENTS.md:L134:forbid-pipe-secrets-downstream | cluster: — -->

- 🔴 **HARD** | `never` | Never put secrets, API tokens, or credentials in ticket descriptions or notes; they stay in agenix
  *<sub>src: ~/.claude/.../memory/reference_paimos_api_access.md L97</sub>*
  <!-- rule_ids: reference_paimos_api_access.md:L97:no-secrets-in-tickets | cluster: — -->

- 🔴 **HARD** | `never` | Never read, cat, or print the secrets file; source it and use the variables instead.
  *<sub>src: ~/Code/fleetcom/AGENTS.md L52</sub>*
  <!-- rule_ids: AGENTS.md:L52:never-print-secrets-file | cluster: — -->

- 🔴 **HARD** | `never` | Never read, cat, print, head, tail, echo, or source secret files to stdout.
  *<sub>src: ~/Code/fleetcom/AGENTS.md L420</sub>*
  <!-- rule_ids: AGENTS.md:L420:never-output-secrets-broad | cluster: — -->

- 🔴 **HARD** | `never` | Never read, cat, print, or source secret/env files like ~/Secrets/*, .env*, .age, /run/secrets/* — direnv loads the env var.
  *<sub>src: ~/Code/fleetcom/.claude/commands/dev.md L25</sub>*
  <!-- rule_ids: dev.md:L25:never-read-secrets | cluster: — -->

- 🔴 **HARD** | `never` | Never run `direnv export <shell>` — it emits resolved env values to stdout
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L122 · incident: 2026-05-13</sub>*
  <!-- rule_ids: AGENTS.md:L122:forbid-direnv-export | cluster: — -->

- 🔴 **HARD** | `never` | Never run `direnv status` when active — may leak a subset of secrets
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L123 · incident: 2026-05-13</sub>*
  <!-- rule_ids: AGENTS.md:L123:forbid-direnv-status-when-active | cluster: — -->

- 🔴 **HARD** | `never` | Never run `env` or `printenv` without naming a specific non-sensitive variable
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L124</sub>*
  <!-- rule_ids: AGENTS.md:L124:forbid-bare-env-printenv | cluster: — -->

- 🔴 **HARD** | `never` | Never run cat/less/head/tail/bat/xxd/od/hexdump/strings on .env, .age, .gpg, .enc, .key, id_*, *_rsa, *_ed25519 or any file under ~/.inspr/secrets/, ~/Secrets/, /run/agenix/, /run/secrets/
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L126-131</sub>*
  <!-- rule_ids: AGENTS.md:L126:forbid-cat-on-secret-files | cluster: — -->

- 🔴 **HARD** | `never` | Never run cat/less/head/tail/echo on .env, .age, .gpg, /run/secrets/*, /run/agenix/* files
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L74-77</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L74:no-cat-on-secret-files-extended | cluster: — -->

- 🔴 **HARD** | `never` | Never run commands that could print secrets to stdout or stderr.
  *<sub>src: ~/Code/fleetcom/.claude/commands/dev.md L26</sub>*
  <!-- rule_ids: dev.md:L26:never-print-secrets | cluster: — -->

- 🔴 **HARD** | `never` | Never run direnv export, direnv status, set, declare -x/-p, compgen -e, export -p, or container/k8s 'resolved' config peeks — they emit resolved environment with secret values
  *<sub>src: ~/Code/inspr/playbook.md L1035 · incident: Day-11</sub>*
  <!-- rule_ids: playbook.md:L1035:never-direnv-export-set-declare | cluster: — -->

- 🔴 **HARD** | `never` | Never run docker exec ... cat /home/node/.env or any container env file
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L76</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L76:no-docker-exec-cat-env | cluster: — -->

- 🔴 **HARD** | `never` | Never run printenv, env, or export without explicit filtering
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L77</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L77:no-printenv-env-export | cluster: — -->

- 🔴 **HARD** | `never` | Never run set, declare -x/-p, compgen -e, or export -p — they print env values
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L125</sub>*
  <!-- rule_ids: AGENTS.md:L125:forbid-set-declare-export-p | cluster: — -->

- 🔴 **HARD** | `never` | Never use docker exec cat /home/node/.env, kubectl get secret -o yaml or describe configmap after env expansion — work from the git source file with placeholders intact
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L133</sub>*
  <!-- rule_ids: AGENTS.md:L133:forbid-container-resolved-config-peek | cluster: — -->

- 🔴 **HARD** | `never` | Never use sed/head/cat on files in ~/Secrets/ even with truncation intent; partial-key leak via sed truncation is real
  *<sub>src: ~/.claude/.../memory/project_inspr.md L234 · incident: 2026-05-11 leak</sub>*
  <!-- rule_ids: project_inspr.md:L234:no-sed-truncation-on-secrets | cluster: — -->

- 🔴 **HARD** | `never` | Never use the Read tool on env-file secrets in /Users/mba/.inspr/secrets/agents/
  *<sub>src: ~/.claude/.../memory/reference_secrets_local_env_pattern.md L23</sub>*
  <!-- rule_ids: reference_secrets_local_env_pattern.md:L23:no-read-tool-on-secrets | cluster: — -->

- 🔴 **HARD** | `never` | Secrets must never appear in stdout, stderr, or any tool output captured by the agent harness
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L111-115 · incident: 2026-05-13</sub>*
  <!-- rule_ids: AGENTS.md:L111:never-print-secrets-to-output | cluster: — -->

- 🔴 **HARD** | `do` | To verify a secret exists, use ls -la only; never print the value
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L80</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L80:verify-secret-via-ls-only | cluster: — -->

- 🔴 **HARD** | `never` | Treat ~/Secrets/*, .env, .env.local, .age, .gpg, /run/secrets/*, /run/agenix/* as secret files; never output their contents.
  *<sub>src: ~/Code/fleetcom/AGENTS.md L421</sub>*
  <!-- rule_ids: AGENTS.md:L421:secret-path-patterns | cluster: — -->

- 🟡 **STRONG** | `always` | Any glob + source/exec/eval loop needs an invariant check on each iteration (content type, file size, magic bytes); or each file's type should be visible from name without inspection
  *<sub>src: ~/Code/inspr/playbook.md L1053 · incident: Day-11</sub>*
  <!-- rule_ids: playbook.md:L1053:glob-source-needs-invariant-check | cluster: — -->

- 🟡 **STRONG** | `never` | Extensions encode content type — don't reuse one extension across types unless every consumer is type-aware (e.g. .env for both env vars and SSH keys cost a leak)
  *<sub>src: ~/Code/inspr/playbook.md L1051 · incident: Day-11</sub>*
  <!-- rule_ids: playbook.md:L1051:naming-conventions-as-security-boundary | cluster: — -->

- 🟡 **STRONG** | `do` | Verify a secret exists with test -n "$VAR"; never print the value.
  *<sub>src: ~/Code/fleetcom/AGENTS.md L425</sub>*
  <!-- rule_ids: AGENTS.md:L425:verify-with-test-n | cluster: — -->


## Topic: security/ssh-keys

- 🔴 **HARD** | `always` | For trust-modifying infra rollouts, design new mechanism to be ADDITIVE alongside the old one; never remove a key during rollout, only add — prevents lockout
  *<sub>src: ~/Code/inspr/playbook.md L518</sub>*
  <!-- rule_ids: playbook.md:L518:additive-trust-rollouts | cluster: — -->

- 🔴 **HARD** | `never` | Never read any ~/.ssh/ file lacking the .pub extension
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L132</sub>*
  <!-- rule_ids: AGENTS.md:L132:forbid-ssh-non-pub-cat | cluster: — -->

- 🔴 **HARD** | `always` | command='...'-restricted SSH keys MUST be preserved verbatim through any keyring abstraction (extraKeys raw-passthrough); abstracting strips restrictions and degrades security
  *<sub>src: ~/Code/inspr/playbook.md L563</sub>*
  <!-- rule_ids: playbook.md:L563:preserve-command-restricted-keys-verbatim | cluster: — -->


## Topic: incident-response/secret-leak

- 🔴 **HARD** | `always` | If a workflow seems to require seeing a secret value (vs using it via env-loaded process), stop and ask the user
  *<sub>src: ~/.claude/.../memory/reference_secrets_local_env_pattern.md L65-67</sub>*
  <!-- rule_ids: reference_secrets_local_env_pattern.md:L67:stop-and-ask-on-secret-doubt | cluster: — -->

- 🔴 **HARD** | `always` | If encrypted file corrupted: STOP, alert user, guide restore from git, rotate credential
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L180</sub>*
  <!-- rule_ids: AGENTS.md:L180:corrupted-encrypted-restore-from-git | cluster: — -->

- 🔴 **HARD** | `always` | If secrets appear in output, STOP — do not run further commands that could touch the same secret pipeline
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L158</sub>*
  <!-- rule_ids: AGENTS.md:L158:secret-leak-stop-pipeline | cluster: — -->

- 🔴 **HARD** | `always` | If secrets appear in tool output: STOP, do not reference, repeat, or quote the values; inform user immediately
  *<sub>src: ~/Code/nixcfg/+agents/rules/SYSOP.md L304 · ~/.claude/.../memory/feedback_agent_protocol.md L81</sub>*
  <!-- rule_ids: SYSOP.md:L304:if-secrets-in-output-stop-do-not-quote,feedback_agent_protocol.md:L81:secret-in-output-stop | cluster: incident-response-secret-leak-008 -->

- 🔴 **HARD** | `always` | If secrets committed: STOP, tell user immediately, discuss, rotate credential; if pushed assume compromised
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L105 · ~/.claude/.../memory/feedback_agent_protocol.md L69</sub>*
  <!-- rule_ids: AGENTS.md:L105:committed-secret-stop-tell-rotate,feedback_agent_protocol.md:L69:secret-leak-stop-rotate | cluster: incident-response-secret-leak-003 -->

- 🔴 **HARD** | `always` | On secret leak, name the affected variables to the user but never the values
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L159</sub>*
  <!-- rule_ids: AGENTS.md:L159:incident-name-vars-not-values | cluster: — -->

- 🔴 **HARD** | `always` | Rotate any secret that appeared in full in transcripts; treat transcripts as leaked-by-default if they ever left the local machine (sent to cloud, shared, uploaded), and prefer immediate rotation over containment.
  *<sub>src: ~/Code/inspr/playbook.md L692 · ~/.claude/.../memory/project_inspr.md L237 · synthesized 2026-05-14 (Phase 4 broadening)</sub>*
  <!-- rule_ids: playbook.md:L692:rotate-secrets-that-appeared-in-transcript,project_inspr.md:L237:rotate-on-transcript-leak | cluster: incident-response-secret-leak-001 -->

- 🔴 **HARD** | `always` | Rotate every exposed credential before continuing after a leak
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L160</sub>*
  <!-- rule_ids: AGENTS.md:L160:rotate-exposed-credentials | cluster: — -->


## Topic: secrets/access-pattern

- 🔴 **HARD** | `never` | Source PPMAPIKEY.env via `set -a; source ~/.inspr/secrets/agents/PPMAPIKEY.env; set +a`; never cat or read the file
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L248 · incident: INSPR-164</sub>*
  <!-- rule_ids: AGENTS.md:L248:never-cat-ppmapikey-env | cluster: — -->

- 🔴 **HARD** | `do` | Use secrets indirectly by sourcing the env file into a subshell environment for a specific command (set -a; source FILE; set +a; cmd)
  *<sub>src: ~/.claude/.../memory/reference_secrets_local_env_pattern.md L36-40</sub>*
  <!-- rule_ids: reference_secrets_local_env_pattern.md:L36:use-subshell-source-pattern | cluster: — -->

- 🟡 **STRONG** | `prefer` | Name materialized env files after the consumer tool's documented env-var convention (e.g. GH_TOKEN.env) so consumer defaults pick up automatically
  *<sub>src: ~/Code/inspr/playbook.md L432</sub>*
  <!-- rule_ids: playbook.md:L432:env-file-naming-consumer-convention | cluster: — -->

- 🟡 **STRONG** | `do` | Source secret env files (e.g. source ~/Secrets/ppm/PPMAPIKEY.env) then use the env var.
  *<sub>src: ~/Code/fleetcom/AGENTS.md L423</sub>*
  <!-- rule_ids: AGENTS.md:L423:source-not-print | cluster: — -->

- 🟡 **STRONG** | `do` | Source ~/Secrets/ppm/PPMAPIKEY.env first, then use $PPMAPIKEY for PPM auth.
  *<sub>src: ~/Code/fleetcom/AGENTS.md L49</sub>*
  <!-- rule_ids: AGENTS.md:L49:source-ppm-env | cluster: — -->

- 🟡 **STRONG** | `do` | Store secrets in ~/Secrets/<NAME>.env so the filename is the env-var name (project convention).
  *<sub>src: ~/Code/fleetcom/AGENTS.md L155-157</sub>*
  <!-- rule_ids: AGENTS.md:L155:secrets-filename-convention | cluster: — -->


## Topic: secrets/agenix-pipeline

- 🔴 **HARD** | `never` | Never run `just rekey` — that command is user-only
  *<sub>src: ~/Code/nixcfg/+agents/rules/SYSOP.md L193 · ~/Code/nixcfg/+agents/rules/SYSOP-GB.md L129</sub>*
  <!-- rule_ids: SYSOP.md:L193:no-rekey-just-rekey-user-only,SYSOP-GB.md:L129:no-rekey-secrets-user-only | cluster: secrets-agenix-pipeline-006 -->

- 🔴 **HARD** | `always` | Pipeline order is ALWAYS declare → encrypt → commit; agenix -e requires the file path declared in secrets/secrets.nix first or errors with 'attribute missing'
  *<sub>src: ~/Code/inspr/playbook.md L641</sub>*
  <!-- rule_ids: playbook.md:L641:agenix-declare-before-edit | cluster: — -->

- 🔴 **HARD** | `always` | Sequence for AGE recipient rotation: add new recipient → agenix --rekey → verify decryption with new key → only THEN remove old recipient → agenix --rekey again
  *<sub>src: ~/Code/inspr/legacy-rsa-key-inventory.md L200-203</sub>*
  <!-- rule_ids: legacy-rsa-key-inventory.md:L201:age-rekey-sequence-add-then-remove | cluster: — -->

- 🟡 **STRONG** | `always` | On every macOS host that becomes an agenix recipient, manually generate a dedicated /etc/ssh/ssh_host_ed25519_key with ssh-keygen as agenix identity anchor
  *<sub>src: ~/Code/inspr/playbook.md L392</sub>*
  <!-- rule_ids: playbook.md:L392:macos-agenix-host-ssh-keygen | cluster: — -->


## Topic: style/communication

- 🟡 **STRONG** | `do` | Search the web early; never guess or invent URLs; quote exact errors; prefer 2026+ sources, fallback older
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L24</sub>*
  <!-- rule_ids: AGENTS.md:L24:web-search-early-no-guess-urls | cluster: — -->

- 🟡 **STRONG** | `always` | When reporting 'no manual intervention needed', verify with the user before claiming it; the agent's tool view may not reflect actual screen state
  *<sub>src: ~/Code/inspr/playbook.md L385</sub>*
  <!-- rule_ids: playbook.md:L385:verify-with-user-before-claiming-no-intervention | cluster: — -->


## Topic: style/file-operations

- 🟡 **STRONG** | `never` | No repo-wide search/replace scripts; keep edits small and reviewable
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L89 · ~/.claude/.../memory/feedback_agent_protocol.md L60</sub>*
  <!-- rule_ids: AGENTS.md:L89:no-repo-wide-search-replace,feedback_agent_protocol.md:L60:no-repo-wide-search-replace | cluster: style-file-operations-009 -->

- 🟡 **STRONG** | `always` | Use rsync --checksum reflexively for any file that 'should have changed but didn't seem to' — default mtime+size check sometimes skips changed files
  *<sub>src: ~/Code/inspr/playbook.md L700</sub>*
  <!-- rule_ids: playbook.md:L700:rsync-checksum-when-transfer-suspect | cluster: — -->

- 🟢 SOFT | `prefer` | On macOS, /etc/ssh/*.pub is world-readable — read pubkeys via plain cat, not sudo, to avoid Touch ID friction
  *<sub>src: ~/Code/inspr/playbook.md L401</sub>*
  <!-- rule_ids: playbook.md:L401:dont-sudo-pubkey-reads-macos | cluster: — -->


## Topic: style/markdown-policy

- 🔴 **HARD** | `never` | Never create new .md files unless user explicitly requests it
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L55</sub>*
  <!-- rule_ids: AGENTS.md:L55:never-create-new-md-files | cluster: — -->

- 🟡 **STRONG** | `do` | If tempted to create a new markdown file, ask first which existing doc to update
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L58</sub>*
  <!-- rule_ids: AGENTS.md:L58:ask-before-creating-md | cluster: — -->

- 🟡 **STRONG** | `prefer` | Prefer editing existing docs over creating new ones
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L56</sub>*
  <!-- rule_ids: AGENTS.md:L56:prefer-edit-existing-docs | cluster: — -->

- 🟡 **STRONG** | `never` | When a path is host-specific, NEVER hardcode it into shared-repo docs — even one that looks 'obviously stale'; unify via source-of-truth materialization layer first
  *<sub>src: ~/Code/inspr/playbook.md L751</sub>*
  <!-- rule_ids: playbook.md:L751:never-hardcode-host-specific-paths-in-shared-docs | cluster: — -->

- 🟡 **STRONG** | `do` | When asked to "document X": update README.md or RUNBOOK.md, do not create a new file
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L57</sub>*
  <!-- rule_ids: AGENTS.md:L57:document-x-update-readme | cluster: — -->


## Topic: tools/agenix

- 🔴 **HARD** | `always` | For multi-isolation-island repos, pass MULTIPLE -i flags to agenix --rekey covering every operator key; rekey is all-or-nothing and aborts on first error
  *<sub>src: ~/Code/inspr/playbook.md L470 · ~/.claude/.../memory/project_inspr.md L171</sub>*
  <!-- rule_ids: playbook.md:L470:agenix-rekey-multi-island-pass-all-keys,project_inspr.md:L171:multi-key-rekey-isolation | cluster: tools-agenix-002 -->

- 🔴 **HARD** | `never` | Never touch .age files without explicit permission (agenix doctrine)
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L227</sub>*
  <!-- rule_ids: AGENTS.md:L227:never-touch-age-files | cluster: — -->

- 🔴 **HARD** | `always` | When invoking agenix from non-interactive context, pipe content via stdin (agenix -e $dst < $src); EDITOR='cp $src' silently encrypts 0 bytes when stdin is non-TTY
  *<sub>src: ~/Code/inspr/playbook.md L897</sub>*
  <!-- rule_ids: playbook.md:L897:agenix-pipe-content-via-stdin | cluster: — -->

- 🟡 **STRONG** | `always` | Always verify with git status + size comparison after agenix --rekey before assuming destructive failure; agenix's atomic-write safety prevents in-place corruption
  *<sub>src: ~/Code/inspr/playbook.md L476</sub>*
  <!-- rule_ids: playbook.md:L476:verify-with-git-status-before-fearing-worst | cluster: — -->

- 🟡 **STRONG** | `always` | Rekey verification needs decryption-with-the-NEW-identity, not just successful rekey exit code (which can mean 'kept old recipients and added nothing')
  *<sub>src: ~/Code/inspr/playbook.md L591</sub>*
  <!-- rule_ids: playbook.md:L591:verify-rekey-with-decrypt-test | cluster: — -->


## Topic: tools/bootstrap-scripts

- 🟡 **STRONG** | `always` | Bootstrap scripts that manage multiple secrets in .env should use per-key boolean pairs (WRITE_X + ROTATE_X), NOT a single --write-env flag that rotates all
  *<sub>src: ~/Code/inspr/playbook.md L741</sub>*
  <!-- rule_ids: playbook.md:L741:per-key-writeback-gates | cluster: — -->

- 🟡 **STRONG** | `prefer` | For self-hostable systems with non-obvious init traps, maintain ONE executable bootstrap as canonical state spec; resist splitting into script + troubleshooting markdown
  *<sub>src: ~/Code/inspr/playbook.md L749</sub>*
  <!-- rule_ids: playbook.md:L749:single-canonical-bootstrap-script | cluster: — -->


## Topic: tools/gh

- 🟡 **STRONG** | `do` | In PR replies cite fix and file/line; resolve threads only after the fix lands
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L64</sub>*
  <!-- rule_ids: AGENTS.md:L64:resolve-threads-only-after-fix | cluster: — -->

- 🟡 **STRONG** | `prefer` | Use gh pr view/diff for PRs (not URLs)
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L21</sub>*
  <!-- rule_ids: AGENTS.md:L21:gh-pr-no-urls | cluster: — -->


## Topic: tools/inspr-doctor

- 🟡 **STRONG** | `prefer` | For security-restricted dirs probe what unprivileged code can actually prove ([ -d $dir ]); don't try to inspect what's intentionally hidden
  *<sub>src: ~/Code/inspr/playbook.md L452</sub>*
  <!-- rule_ids: playbook.md:L452:probe-only-what-unprivileged-can-prove | cluster: — -->


## Topic: tools/just

- 🟡 **STRONG** | `always` | In just recipe docstrings, show invocations with positional args only — never name=value syntax which is parsed as a literal string passed to first positional arg
  *<sub>src: ~/Code/inspr/playbook.md L474</sub>*
  <!-- rule_ids: playbook.md:L474:just-recipe-args-positional-only | cluster: — -->


## Topic: tools/script-design

- 🔴 **HARD** | `always` | Every script that touches a remote auth system should default to read-only/preserve and require explicit opt-in for any state change
  *<sub>src: ~/Code/inspr/playbook.md L690</sub>*
  <!-- rule_ids: playbook.md:L690:default-readonly-opt-in-mutation | cluster: — -->

- 🟡 **STRONG** | `always` | In auto-detect heuristics that depend on tool presence, normalize the environment (PATH export) BEFORE probing it with command -v
  *<sub>src: ~/Code/inspr/playbook.md L450</sub>*
  <!-- rule_ids: playbook.md:L450:export-path-before-command-v | cluster: — -->

- 🟡 **STRONG** | `always` | When sed-renaming functions across a known set, ALWAYS use comm(1) over BOTH function-name lists to find the FULL collision set BEFORE writing the rename loop — don't iterate
  *<sub>src: ~/Code/inspr/playbook.md L934</sub>*
  <!-- rule_ids: playbook.md:L934:use-comm-to-find-full-collision-set | cluster: — -->


## Topic: tools/shell-quoting

- 🟡 **STRONG** | `avoid` | Avoid English-contraction apostrophes in awk/shell embedded in single-quoted strings (Nix-rendered or otherwise) — they prematurely terminate the quoted region
  *<sub>src: ~/Code/inspr/playbook.md L501</sub>*
  <!-- rule_ids: playbook.md:L501:no-apostrophes-in-single-quoted-shell | cluster: — -->


## Topic: tools/ssh

- 🟡 **STRONG** | `always` | For local-user scope in ssh_config Match use LocalUser (or LocalHost / OriginalHost); bare User/Host describe TARGET, not ORIGIN
  *<sub>src: ~/Code/inspr/RESUMING-2026-05-13.md L45</sub>*
  <!-- rule_ids: RESUMING-2026-05-13.md:L45:ssh-localuser-for-origin-scope | cluster: — -->

- 🟡 **STRONG** | `always` | In ssh_config Match, use LocalUser/LocalHost/OriginalHost for origin-scoping; bare User/Host describe the connection TARGET, not the local user running ssh
  *<sub>src: ~/Code/inspr/playbook.md L960</sub>*
  <!-- rule_ids: playbook.md:L960:ssh-match-localuser-for-origin | cluster: — -->

- 🟡 **STRONG** | `do` | imac0 exception: ssh markus@imac0.lan; user is markus, not mba
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L215 · ~/.claude/.../memory/feedback_agent_protocol.md L144</sub>*
  <!-- rule_ids: AGENTS.md:L215:imac0-ssh-uses-markus,feedback_agent_protocol.md:L144:ssh-imac0-markus-user | cluster: tools-ssh-002 -->


## Topic: tools/trash

- 🔴 **HARD** | `never` | For deletes use trash, never rm -rf
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L23 · ~/.claude/.../memory/feedback_agent_protocol.md L48</sub>*
  <!-- rule_ids: AGENTS.md:L23:use-trash-not-rm,feedback_agent_protocol.md:L48:trash-not-rm | cluster: tools-trash-001 -->


## Topic: process/build-test

- 🟡 **STRONG** | `do` | Keep notes short; update docs when behavior or API changes (no ship without docs)
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L51</sub>*
  <!-- rule_ids: AGENTS.md:L51:update-docs-on-behavior-change | cluster: — -->

- 🟡 **STRONG** | `do` | On CI red: gh run list/view, rerun, fix, push, repeat to green
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L77 · ~/.claude/.../memory/feedback_agent_protocol.md L126</sub>*
  <!-- rule_ids: AGENTS.md:L77:fix-ci-til-green,feedback_agent_protocol.md:L126:ci-red-iterate-to-green | cluster: process-build-test-003 -->

- 🟡 **STRONG** | `do` | Use the repo package manager and runtime; no swaps without approval
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L68</sub>*
  <!-- rule_ids: AGENTS.md:L68:repo-package-manager-no-swaps | cluster: — -->


## Topic: process/config-management

- 🟡 **STRONG** | `always` | For any tool with both legacy non-XDG and XDG config locations, declarative config managers should warn loudly when both files exist on the same host
  *<sub>src: ~/Code/inspr/playbook.md L442</sub>*
  <!-- rule_ids: playbook.md:L442:warn-on-dual-config-files | cluster: — -->


## Topic: process/critical-thinking

- 🔴 **HARD** | `always` | Always verify the full context of edits; read before replacing
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L196 · ~/.claude/.../memory/feedback_agent_protocol.md L131</sub>*
  <!-- rule_ids: AGENTS.md:L196:read-before-replace,feedback_agent_protocol.md:L131:verify-context-before-edits | cluster: process-critical-thinking-012 -->

- 🔴 **HARD** | `do` | Clarity over speed: if uncertain, ask before proceeding; better one question than three bugs
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L195 · ~/.claude/.../memory/feedback_agent_protocol.md L130</sub>*
  <!-- rule_ids: AGENTS.md:L195:clarity-over-speed-ask-when-unsure,feedback_agent_protocol.md:L130:clarity-over-speed | cluster: process-critical-thinking-011 -->

- 🔴 **HARD** | `always` | When automation seems stuck, investigate via systemctl status + journalctl BEFORE force-killing; operator-induced fix attempts often cause more damage than the original problem
  *<sub>src: ~/Code/inspr/playbook.md L516 · incident: NIX-101</sub>*
  <!-- rule_ids: playbook.md:L516:investigate-before-force-killing | cluster: — -->

- 🟡 **STRONG** | `always` | Always verify post-action (git status, ls -la, decrypt-test, etc.); the verification step is part of the operation, not optional cleanup
  *<sub>src: ~/Code/inspr/playbook.md L493</sub>*
  <!-- rule_ids: playbook.md:L493:always-verify-post-action | cluster: — -->

- 🟡 **STRONG** | `always` | Automation patterns that work interactively can fail silently in non-interactive contexts — always verify outputs structurally (size, content sniff), not just by exit code
  *<sub>src: ~/Code/inspr/playbook.md L897</sub>*
  <!-- rule_ids: playbook.md:L897:verify-outputs-structurally-not-by-exit-code | cluster: — -->

- 🟡 **STRONG** | `always` | Before assuming an infrastructure surprise is a real bug, gather concrete journal evidence (timestamps, systemd state transitions, operator commands intervened)
  *<sub>src: ~/Code/inspr/playbook.md L524 · incident: NIX-101</sub>*
  <!-- rule_ids: playbook.md:L524:gather-evidence-before-bug-classification | cluster: — -->

- 🟡 **STRONG** | `dont` | Don't guess or invent URLs; quote exact errors
  *<sub>src: ~/.claude/.../memory/feedback_agent_protocol.md L115</sub>*
  <!-- rule_ids: feedback_agent_protocol.md:L115:dont-invent-urls-quote-errors | cluster: — -->

- 🟡 **STRONG** | `do` | Fix root cause, not band-aid
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L197 · ~/.claude/.../memory/feedback_agent_protocol.md L132</sub>*
  <!-- rule_ids: AGENTS.md:L197:fix-root-cause-not-bandaid,feedback_agent_protocol.md:L132:fix-root-cause-not-bandaid | cluster: process-critical-thinking-013 -->

- 🟡 **STRONG** | `do` | Follow links until domain makes sense; honor existing patterns
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L50</sub>*
  <!-- rule_ids: AGENTS.md:L50:honor-existing-patterns | cluster: — -->

- 🟡 **STRONG** | `always` | Institutional advice from a vendor optimizes for the vendor's preferred shape — useful signal, not authoritative; re-derive against own axes (portability, rotation, scope) before adopting
  *<sub>src: ~/Code/inspr/playbook.md L804</sub>*
  <!-- rule_ids: playbook.md:L804:re-derive-vendor-advice-against-own-axes | cluster: — -->

- 🟡 **STRONG** | `do` | On conflicts, call them out and pick the safer path
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L199 · ~/.claude/.../memory/feedback_agent_protocol.md L134</sub>*
  <!-- rule_ids: AGENTS.md:L199:conflicts-pick-safer-path,feedback_agent_protocol.md:L134:on-conflicts-pick-safer | cluster: process-critical-thinking-015 -->

- 🟡 **STRONG** | `always` | Re-survey existing tooling on --help before scoping any 'extend X' ticket; periodic ticket reality-check is its own backlog hygiene activity
  *<sub>src: ~/Code/inspr/playbook.md L438</sub>*
  <!-- rule_ids: playbook.md:L438:re-survey-tools-before-extending | cluster: — -->

- 🟡 **STRONG** | `always` | When framing 'smaller=safer vs bigger=right', verify the bigger option is actually feasible TODAY (research blockers/issues); defer because of brittleness, not size
  *<sub>src: ~/Code/inspr/playbook.md L635</sub>*
  <!-- rule_ids: playbook.md:L635:verify-bigger-option-feasible-today | cluster: — -->

- 🟡 **STRONG** | `always` | When integrating against unfamiliar API surface — especially across version-spans — always probe actual endpoint behavior before designing the idempotency strategy
  *<sub>src: ~/Code/inspr/playbook.md L739</sub>*
  <!-- rule_ids: playbook.md:L739:probe-before-implement | cluster: — -->

- 🟡 **STRONG** | `prefer` | When joining an existing repo with its own pattern, prefer hybrid coexistence + a follow-up ticket over unilateral refactor that touches production-prod code
  *<sub>src: ~/Code/inspr/playbook.md L468</sub>*
  <!-- rule_ids: playbook.md:L468:hybrid-coexistence-over-unilateral-refactor | cluster: — -->

- 🟡 **STRONG** | `do` | When unsure read more code; if still stuck ask with short option list
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L198</sub>*
  <!-- rule_ids: AGENTS.md:L198:read-more-then-ask-options | cluster: — -->

- 🟢 SOFT | `do` | Treat unrecognized changes as another agents work; keep going on your scope and stop+ask only on issues
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L200</sub>*
  <!-- rule_ids: AGENTS.md:L200:unrecognized-changes-assume-other-agent | cluster: — -->


## Topic: process/design-doctrine

- 🟡 **STRONG** | `prefer` | For stable infrastructure credentials, prefer primitives that NEVER rotate (deploy keys, classic PATs) or auto-rotate invisibly (App tokens, OIDC); manual rotation only where rotation is the point
  *<sub>src: ~/Code/inspr/playbook.md L802</sub>*
  <!-- rule_ids: playbook.md:L802:rotation-burden-first-class-dimension | cluster: — -->

- 🟡 **STRONG** | `always` | When a design decision goes through many reorientations, capture the trail (what was tried/rejected and why) so alternatives don't get re-litigated every session
  *<sub>src: ~/Code/inspr/playbook.md L806</sub>*
  <!-- rule_ids: playbook.md:L806:capture-pivot-trail-for-design-decisions | cluster: — -->

- 🟡 **STRONG** | `always` | When designing for a fleet, draw the 'who owns this identity?' question explicitly — human vs machine; the answer rules out half the credential primitives immediately
  *<sub>src: ~/Code/inspr/playbook.md L905</sub>*
  <!-- rule_ids: playbook.md:L905:draw-identity-question-explicitly | cluster: — -->

- 🟡 **STRONG** | `always` | When picking a credential primitive, first ask 'is this identity owned by a human or by a machine?' — the answer rules out half the options immediately
  *<sub>src: ~/Code/inspr/playbook.md L800</sub>*
  <!-- rule_ids: playbook.md:L800:identity-question-rules-out-half-options | cluster: — -->


## Topic: process/host-recovery

- 🟡 **STRONG** | `always` | SSH-back is necessary but not sufficient post-reboot; build a routine that waits for SSH + ICMP + expected systemd targets active + expected container count
  *<sub>src: ~/Code/inspr/playbook.md L557</sub>*
  <!-- rule_ids: playbook.md:L557:post-reboot-health-check-routine | cluster: — -->


## Topic: process/migrations

- 🟡 **STRONG** | `always` | For declarative-replaces-imperative file migration: backup → activate → verify → strip the unmanaged region; trade off in favor of redundancy over potential lockout
  *<sub>src: ~/Code/inspr/playbook.md L593</sub>*
  <!-- rule_ids: playbook.md:L593:two-step-migration-strip-after-verify | cluster: — -->


## Topic: process/onboarding

- 🟡 **STRONG** | `always` | Onboarding tooling must always distinguish host and service URL explicitly in any setup form; never let one default-fill into the other
  *<sub>src: ~/Code/inspr/playbook.md L364-367</sub>*
  <!-- rule_ids: playbook.md:L364:distinguish-host-and-service-url | cluster: — -->

- 🟡 **STRONG** | `always` | Probe responses should be validated by examining body and headers, not just the status code; healthchecks must assert on response content
  *<sub>src: ~/Code/inspr/playbook.md L373</sub>*
  <!-- rule_ids: playbook.md:L373:validate-probe-response-content | cluster: — -->

- 🟡 **STRONG** | `prefer` | Test URLs by probing for protocol-shaped responses (e.g. Tailscale-shaped JSON), not merely 'HTTPS works' or HTTP status code
  *<sub>src: ~/Code/inspr/playbook.md L366-367</sub>*
  <!-- rule_ids: playbook.md:L366:probe-protocol-shape | cluster: — -->


## Topic: process/pre-commit-checklist

- 🔴 **HARD** | `always` | Run mental pre-flight before every Bash command in secret-adjacent context: could stdout/stderr contain a secret, does it touch secret paths, does it involve env-printing tools, did a filtered command return empty
  *<sub>src: ~/.claude/.../memory/reference_secrets_local_env_pattern.md L57-63</sub>*
  <!-- rule_ids: reference_secrets_local_env_pattern.md:L57:secret-preflight-checklist | cluster: — -->

- 🟡 **STRONG** | `always` | After shipping anything claimed-as-done, do a structured C/H/M/O severity pass through the artifacts asking 'would this withstand a tough security and validity audit?'
  *<sub>src: ~/Code/inspr/playbook.md L460</sub>*
  <!-- rule_ids: playbook.md:L460:self-audit-before-claiming-done | cluster: — -->

- 🟡 **STRONG** | `do` | Before handoff, run the full gate: lint, typecheck, tests, docs
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L76</sub>*
  <!-- rule_ids: AGENTS.md:L76:run-full-gate-before-handoff | cluster: — -->


## Topic: process/rollout-discipline

- 🟡 **STRONG** | `prefer` | For prod-adjacent first cutovers use 1 step = 1 commit = 1 validation gate; once pattern is proven, subsequent hosts can absorb same N changes as one atomic commit
  *<sub>src: ~/Code/inspr/playbook.md L968</sub>*
  <!-- rule_ids: playbook.md:L968:granularity-inverse-to-pattern-proof | cluster: — -->


## Topic: process/sync-triad

- 🔴 **HARD** | `always` | Prime Directive: keep config, docs, and tests in sync
  *<sub>src: ~/Code/nixcfg/+agents/rules/SYSOP.md L255 · ~/Code/nixcfg/+agents/rules/SYSOP-GB.md L162</sub>*
  <!-- rule_ids: SYSOP.md:L255:prime-directive-config-docs-tests,SYSOP-GB.md:L162:prime-directive-config-docs-tests-gb | cluster: process-sync-triad-001 -->


## Topic: workflow/ppm

- 🔴 **HARD** | `do` | Mark PPM tickets as done only when acceptance criteria are met.
  *<sub>src: ~/Code/fleetcom/AGENTS.md L43</sub>*
  <!-- rule_ids: AGENTS.md:L43:done-means-done | cluster: — -->

- 🟡 **STRONG** | `always` | Always reference PPM tickets by human-visible key (e.g. FLEET-79) in chat, commits, branches, PR titles; numeric DB id is for API calls only.
  *<sub>src: ~/Code/fleetcom/AGENTS.md L44</sub>*
  <!-- rule_ids: AGENTS.md:L44:ticket-key-style | cluster: — -->

- 🟡 **STRONG** | `do` | Before starting work check PPM for a backing ticket; if none exists create one first.
  *<sub>src: ~/Code/fleetcom/AGENTS.md L39</sub>*
  <!-- rule_ids: AGENTS.md:L39:ppm-backing-ticket | cluster: — -->

- 🟡 **STRONG** | `dont` | Create epics and tickets in PPM. Do not create local backlog files.
  *<sub>src: ~/Code/fleetcom/AGENTS.md L40</sub>*
  <!-- rule_ids: AGENTS.md:L40:no-local-backlog-files | cluster: — -->

- 🟡 **STRONG** | `do` | Update PPM ticket status as work progresses (new -> in-progress -> done).
  *<sub>src: ~/Code/fleetcom/AGENTS.md L41</sub>*
  <!-- rule_ids: AGENTS.md:L41:ppm-status-updates | cluster: — -->

- 🟡 **STRONG** | `do` | When work is done update PPM ticket status and stop the timer.
  *<sub>src: ~/Code/fleetcom/.claude/commands/dev.md L22 · ~/Code/nixcfg/+agents/commands/ops.md L8</sub>*
  <!-- rule_ids: dev.md:L22:ppm-on-done,ops.md:L8:update-ppm-and-stop-timers | cluster: workflow-ppm-002 -->


## Topic: pacing/long-running

- 🟡 **STRONG** | `do` | Background or zellij session for long jobs
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L69 · ~/.claude/.../memory/feedback_agent_protocol.md L120</sub>*
  <!-- rule_ids: AGENTS.md:L69:long-jobs-background-or-zellij,feedback_agent_protocol.md:L120:long-running-background-or-zellij | cluster: pacing-long-running-002 -->

- 🟡 **STRONG** | `do` | Prefix long-running commands (>10s) with date && (bash) or date; and (fish) for timestamping
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L70-72</sub>*
  <!-- rule_ids: AGENTS.md:L70:prefix-long-cmds-with-date | cluster: — -->


## Topic: git/identity

- 🔴 **HARD** | `never` | Never invent identity values (placeholder emails, names, etc.) — ask the user or fail loudly; placeholders end up permanent in commit metadata
  *<sub>src: ~/Code/inspr/playbook.md L354-357</sub>*
  <!-- rule_ids: playbook.md:L355:never-invent-identity | cluster: — -->

- 🔴 **HARD** | `never` | Never invent placeholder identity values like user@example.com or markus@inspr.local; if tempted to fabricate one, stop and ask the user or fail loudly
  *<sub>src: ~/.claude/.../memory/user_identity.md L15 · incident: first-session lesson</sub>*
  <!-- rule_ids: user_identity.md:L15:never-invent-placeholder-identity | cluster: — -->

- 🟡 **STRONG** | `always` | Any tool auto-generating includeIf hasconfig:remote.*.url rules must produce paired HTTPS-anchored AND SSH-anchored patterns since * does not cross URL component boundaries
  *<sub>src: ~/Code/inspr/playbook.md L434</sub>*
  <!-- rule_ids: playbook.md:L434:git-hasconfig-paired-patterns | cluster: — -->

- 🟡 **STRONG** | `prefer` | Prefer content-derived rules (e.g. hasconfig:remote.*.url) over enumeration-based rules (gitdir lists) whenever the underlying truth is queryable
  *<sub>src: ~/Code/inspr/playbook.md L436</sub>*
  <!-- rule_ids: playbook.md:L436:prefer-content-derived-rules | cluster: — -->


## Topic: git/safety

- 🔴 **HARD** | `never` | If pre-commit hooks modify files, stage them and create a fresh commit attempt; never amend
  *<sub>src: ~/Code/nixcfg/+agents/commands/push.md L10</sub>*
  <!-- rule_ids: push.md:L10:precommit-fix-stage-fresh-not-amend | cluster: — -->

- 🔴 **HARD** | `never` | Never run `git push --force` without explicit user request
  *<sub>src: ~/Code/nixcfg/+agents/rules/SYSOP.md L165 · ~/Code/nixcfg/+agents/rules/SYSOP-GB.md L116</sub>*
  <!-- rule_ids: SYSOP.md:L165:never-force-push-without-explicit,SYSOP-GB.md:L116:no-force-push-without-explicit | cluster: git-safety-010 -->

- 🔴 **HARD** | `never` | No amend unless asked
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L90</sub>*
  <!-- rule_ids: AGENTS.md:L90:no-amend-unless-asked | cluster: — -->

- 🔴 **HARD** | `always` | On any /push-family slash command (`/push`, `/pushall`): proceed without asking confirmation, but STOP and alert the user if the diff or working tree shows potential secrets or unexpected files before any push happens.
  *<sub>src: ~/Code/nixcfg/+agents/commands/push.md L15 · ~/Code/nixcfg/+agents/commands/pushall.md L17 · synthesized 2026-05-14 (Phase 4 broadening)</sub>*
  <!-- rule_ids: push.md:L15:no-confirmation-stop-on-secrets,pushall.md:L17:stop-on-secrets-in-pushall | cluster: git-safety-017 -->

- 🟡 **STRONG** | `do` | After commits succeed, run `git pull --rebase && git push`
  *<sub>src: ~/Code/nixcfg/+agents/commands/push.md L11</sub>*
  <!-- rule_ids: push.md:L11:pull-rebase-then-push | cluster: — -->

- 🟡 **STRONG** | `always` | Always re-git-add edited files before commit, or use git commit -a for tracked files; the AM letter combination warns of stale staged versions
  *<sub>src: ~/Code/inspr/playbook.md L428</sub>*
  <!-- rule_ids: playbook.md:L428:re-stage-before-commit | cluster: — -->

- 🟡 **STRONG** | `do` | Branch changes require user consent
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L86 · ~/.claude/.../memory/feedback_agent_protocol.md L57</sub>*
  <!-- rule_ids: AGENTS.md:L86:branch-changes-need-consent,feedback_agent_protocol.md:L57:branch-changes-need-consent | cluster: git-safety-006 -->

- 🟡 **STRONG** | `do` | Group changes into logical commits; do not lump unrelated changes into one commit
  *<sub>src: ~/Code/nixcfg/+agents/commands/push.md L4</sub>*
  <!-- rule_ids: push.md:L4:group-changes-into-logical-commits | cluster: — -->

- 🟡 **STRONG** | `do` | Multi-agent: check git status/diff before edits; ship small commits
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L92 · ~/.claude/.../memory/feedback_agent_protocol.md L63</sub>*
  <!-- rule_ids: AGENTS.md:L92:multi-agent-check-status-first,feedback_agent_protocol.md:L63:multi-agent-status-first | cluster: git-safety-009 -->

- 🟡 **STRONG** | `do` | On /push, commit and push the current working directory repo only
  *<sub>src: ~/Code/nixcfg/+agents/commands/push.md L1</sub>*
  <!-- rule_ids: push.md:L1:push-cwd-repo-only | cluster: — -->

- 🟡 **STRONG** | `do` | On /pushall do not ask for confirmation — just do it
  *<sub>src: ~/Code/nixcfg/+agents/commands/pushall.md L27</sub>*
  <!-- rule_ids: pushall.md:L27:pushall-no-confirmation | cluster: — -->

- 🟡 **STRONG** | `do` | On /pushall process all listed workspace repos in order: nixcfg, oc-workspace-percy, oc-workspace-merlin
  *<sub>src: ~/Code/nixcfg/+agents/commands/pushall.md L1</sub>*
  <!-- rule_ids: pushall.md:L1:pushall-process-all-repos-in-order | cluster: — -->

- 🟡 **STRONG** | `do` | Use the repo existing commit message style (check git log --oneline -10)
  *<sub>src: ~/Code/nixcfg/+agents/commands/push.md L9</sub>*
  <!-- rule_ids: push.md:L9:use-existing-commit-style | cluster: — -->

- 🟢 SOFT | `do` | For big review use git --no-pager diff --color=never
  *<sub>src: ~/Code/nixcfg/+agents/rules/AGENTS.md L91 · ~/.claude/.../memory/feedback_agent_protocol.md L62</sub>*
  <!-- rule_ids: AGENTS.md:L91:big-review-no-pager-no-color,feedback_agent_protocol.md:L62:big-review-no-pager | cluster: git-safety-008 -->


## Topic: nix/flakes

- 🟡 **STRONG** | `always` | Automation must git add -N (intent-to-add) any files it generates BEFORE running flake operations because flakes only see git-tracked files
  *<sub>src: ~/Code/inspr/playbook.md L396-399</sub>*
  <!-- rule_ids: playbook.md:L398:git-add-N-before-flake-eval | cluster: — -->


## Topic: nix/modules

- 🟡 **STRONG** | `always` | Any derivation that programmatically transforms an externally-versioned input MUST include sanity asserts on output (positive markers + inverse checks) — cheap insurance against upstream drift
  *<sub>src: ~/Code/inspr/playbook.md L966</sub>*
  <!-- rule_ids: playbook.md:L966:build-time-asserts-against-upstream-drift | cluster: — -->

- 🟡 **STRONG** | `prefer` | At module design time, default to multi-user shapes (users.<name>.{trust,...}) over single-user — costs nothing for common case, prevents future breaking refactor
  *<sub>src: ~/Code/inspr/playbook.md L561</sub>*
  <!-- rule_ids: playbook.md:L561:multi-user-shape-by-default | cluster: — -->

- 🟡 **STRONG** | `always` | Build-time sanity asserts in pkgs.runCommand derivations are cheap insurance against upstream API drift — positive checks (markers present) + inverse checks (no old marker remaining)
  *<sub>src: ~/Code/inspr/RESUMING-2026-05-13.md L51</sub>*
  <!-- rule_ids: RESUMING-2026-05-13.md:L51:build-time-asserts-runCommand | cluster: — -->

- 🟡 **STRONG** | `always` | For HM-on-NixOS modules consuming flake inputs, always import upstream HM modules at the NixOS-scope wire-up site, never in HM-side files (unless extraSpecialArgs is wired)
  *<sub>src: ~/Code/inspr/playbook.md L514</sub>*
  <!-- rule_ids: playbook.md:L514:capture-inputs-at-nixos-scope | cluster: — -->

- 🟡 **STRONG** | `always` | For system-wide ssh CLIENT config (Match blocks, IdentityFile pinning), always use programs.ssh.extraConfig; never rely on /etc/ssh/ssh_config.d/ glob-include — verify with ssh -v
  *<sub>src: ~/Code/inspr/playbook.md L958</sub>*
  <!-- rule_ids: playbook.md:L958:programs-ssh-extraConfig-not-glob-include | cluster: — -->

- 🟡 **STRONG** | `prefer` | In Nix, validation throws must be on a path that's guaranteed-evaluated; lazy-bound let _ = X doesn't count — use builtins.seq or move into config.assertions
  *<sub>src: ~/Code/inspr/playbook.md L846</sub>*
  <!-- rule_ids: playbook.md:L846:nix-validation-on-evaluated-path | cluster: — -->

- 🟡 **STRONG** | `always` | NixOS programs.ssh client side does NOT include /etc/ssh/ssh_config.d/*.conf; always use programs.ssh.extraConfig for system-wide ssh-client Match blocks
  *<sub>src: ~/Code/inspr/RESUMING-2026-05-13.md L43</sub>*
  <!-- rule_ids: RESUMING-2026-05-13.md:L43:programs-ssh-not-glob-include | cluster: — -->

- 🟡 **STRONG** | `always` | builtins.readDir patterns should warn or fail loudly when they discover zero files in a directory the user clearly intended to use
  *<sub>src: ~/Code/inspr/playbook.md L399</sub>*
  <!-- rule_ids: playbook.md:L399:warn-on-readDir-zero-files | cluster: — -->

- 🟢 SOFT | `prefer` | NixOS git build reads /etc/gitconfig by default; environment.etc.gitconfig.text works for system-wide url.insteadOf without needing /root/.gitconfig
  *<sub>src: ~/Code/inspr/RESUMING-2026-05-13.md L47</sub>*
  <!-- rule_ids: RESUMING-2026-05-13.md:L47:etc-gitconfig-read-by-nixos-git | cluster: — -->


## Topic: nix/strings

- 🟡 **STRONG** | `avoid` | Treat all text inside Nix '' multiline strings as Nix tokens including # comments; prefer pkgs.writeShellApplication store paths to embedded heredocs
  *<sub>src: ~/Code/inspr/playbook.md L458</sub>*
  <!-- rule_ids: playbook.md:L458:no-bash-comments-inside-nix-multiline-strings | cluster: — -->


## Topic: nix/syntax

- 🟡 **STRONG** | `prefer` | Nix or keyword only works in attrs.attr or default form — NOT as binary infix; reach for explicit if over clever or when in doubt
  *<sub>src: ~/Code/inspr/playbook.md L907</sub>*
  <!-- rule_ids: playbook.md:L907:explicit-conditional-over-clever-or | cluster: — -->


## Topic: nixos/activation

- 🔴 **HARD** | `always` | Always run nix profile list on a macOS host BEFORE home-manager switch if there's any chance of imperative installs; resolve conflicts FIRST to avoid bricked profile
  *<sub>src: ~/Code/inspr/playbook.md L601</sub>*
  <!-- rule_ids: playbook.md:L601:nix-profile-list-before-hm-switch | cluster: — -->

- 🔴 **HARD** | `always` | On HM/NixOS activation failure, verify (a) login shell still execable, (b) PATH binaries present, (c) SSH still functional, (d) home-manager itself still in profile
  *<sub>src: ~/Code/inspr/playbook.md L605</sub>*
  <!-- rule_ids: playbook.md:L605:verify-blast-radius-after-activation-failure | cluster: — -->

- 🟡 **STRONG** | `always` | Activation scripts that create immutable artifacts must remove-then-recreate, not overwrite-in-place; locked file modes block subsequent rewrites
  *<sub>src: ~/Code/inspr/playbook.md L440</sub>*
  <!-- rule_ids: playbook.md:L440:rm-before-recreate-immutable-files | cluster: — -->

- 🟡 **STRONG** | `always` | After HM activation failure, verify the file you came to change is actually changed before declaring victory; early-step failure can silently bypass later steps
  *<sub>src: ~/Code/inspr/playbook.md L587</sub>*
  <!-- rule_ids: playbook.md:L587:verify-changed-file-changed-after-failed-activation | cluster: — -->

- 🟡 **STRONG** | `always` | In HM activation DAGs, treat umask (and process-state mutables like cd, set -e) as something predecessors may have modified — always reset to expected value at top of script
  *<sub>src: ~/Code/inspr/playbook.md L1098-1100 · incident: Day-11</sub>*
  <!-- rule_ids: playbook.md:L1098:reset-umask-at-activation-script-start | cluster: — -->

- 🟡 **STRONG** | `always` | In HM activation scripts, treat PATH as minimal-coreutils; either reference system tools by absolute path (/usr/bin/awk) or use bash builtins
  *<sub>src: ~/Code/inspr/playbook.md L633</sub>*
  <!-- rule_ids: playbook.md:L633:hm-activation-path-no-awk | cluster: — -->

- 🟡 **STRONG** | `always` | In activation scripts that create protective directories, open the dir with write perms first, do all writes, lock to restrictive mode last
  *<sub>src: ~/Code/inspr/playbook.md L418</sub>*
  <!-- rule_ids: playbook.md:L418:activation-write-first-lock-last | cluster: — -->

- 🟡 **STRONG** | `always` | When mixing package-manager-installed binaries with Nix-managed wrappers, the activation DAG must explicitly sequence install → wrap (entryAfter); implicit ordering doesn't work
  *<sub>src: ~/Code/inspr/playbook.md L792</sub>*
  <!-- rule_ids: playbook.md:L792:hm-activation-order-wrap-after-install | cluster: — -->


## Topic: nixos/build-safety

- 🔴 **HARD** | `never` | Never systemctl stop nixos-rebuild-switch-to-configuration.service on the 'already loaded' error; wait for is-active inactive or use systemctl reset-failed
  *<sub>src: ~/Code/inspr/playbook.md L516 · incident: NIX-101</sub>*
  <!-- rule_ids: playbook.md:L516:never-systemctl-stop-active-rebuild | cluster: — -->

- 🟡 **STRONG** | `prefer` | Before nixos-rebuild test/switch on a host you haven't recently rebooted, check for staged-kernel state; if pending prefer nixos-rebuild boot + scheduled reboot
  *<sub>src: ~/Code/inspr/playbook.md L555</sub>*
  <!-- rule_ids: playbook.md:L555:prefer-boot-over-switch-with-staged-kernel | cluster: — -->

- 🟡 **STRONG** | `prefer` | For generic glibc binaries failing on NixOS with 'no such file' on existing executable, enable programs.nix-ld — fixes whole class of binaries vs steam-run/patchelf for one
  *<sub>src: ~/Code/inspr/playbook.md L788</sub>*
  <!-- rule_ids: playbook.md:L788:nix-ld-for-generic-glibc-binaries | cluster: — -->

- 🟡 **STRONG** | `avoid` | With NixOS users.mutableUsers=true (default), hashedPassword is only consumed at INITIAL user creation; subsequent rebuilds don't propagate — use hashedPasswordFile instead
  *<sub>src: ~/Code/inspr/playbook.md L499 · incident: NIX-79</sub>*
  <!-- rule_ids: playbook.md:L499:nixos-mutable-users-hashedPassword-once | cluster: — -->

- 🟢 SOFT | `prefer` | When pulling on remote host before nixos-rebuild, distinguish flake-relevant files (.nix, flake.lock, imports) from incidental files; only the former block deployment
  *<sub>src: ~/Code/inspr/playbook.md L565</sub>*
  <!-- rule_ids: playbook.md:L565:flake-irrelevant-conflicts-dont-block-rebuild | cluster: — -->


## Topic: nixos/debugging

- 🟡 **STRONG** | `prefer` | When a module test fails opaquely, drop the harness and call lib.evalModules directly on a minimal stub to see the raw config tree — splits module-vs-harness bugs
  *<sub>src: ~/Code/inspr/playbook.md L842</sub>*
  <!-- rule_ids: playbook.md:L842:debug-module-via-direct-evalModules | cluster: — -->

- 🟡 **STRONG** | `prefer` | When nix flake check fails with confusing trace, don't chase the trace at face value — bisect by evaluating each top-level output category in isolation
  *<sub>src: ~/Code/inspr/playbook.md L478</sub>*
  <!-- rule_ids: playbook.md:L478:bisect-flake-check-by-output | cluster: — -->


## Topic: infra/tailscale

- 🔴 **HARD** | `never` | Tailscale --login-server must point at the service URL (e.g. hs.barta.cm), never the container host hostname (e.g. cs0.barta.cm)
  *<sub>src: ~/Code/inspr/playbook.md L88-89</sub>*
  <!-- rule_ids: playbook.md:L89:tailscale-login-server-service-url | cluster: — -->

- 🟡 **STRONG** | `always` | Any tailscale up automation must always pass --login-server explicitly because macOS Tailscale daemon prefs do not reliably survive reboot
  *<sub>src: ~/Code/inspr/playbook.md L371</sub>*
  <!-- rule_ids: playbook.md:L371:tailscale-pass-login-server-explicitly | cluster: — -->

- 🟡 **STRONG** | `never` | Do not sudo the macOS Tailscale CLI; daemon runs as root via system extension and CLI talks via Unix socket as the regular user
  *<sub>src: ~/Code/inspr/playbook.md L149-157</sub>*
  <!-- rule_ids: playbook.md:L151:no-sudo-tailscale-macos | cluster: — -->

<!--
  Note: the `agent-protocol/session-startup` topic added 2026-05-15 morning
  (INSPR-190 transitional startup-hint, tagged sunset 2026-06-15) was
  REMOVED later the same day by INSPR-189 Phase 6. The kernel
  (AGENTS-KERNEL.md) router supersedes that transitional hint.
-->
