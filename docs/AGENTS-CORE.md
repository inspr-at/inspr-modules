# AGENTS — Core

*Layer: `universal` · Synthesized 2026-05-14 by INSPR-179 Phase 4 · This layer holds 199 rules. (Post-Phase-6: this file is no longer auto-loaded; it remains as exhaustive reference. Slash commands `/dev /ops /secrets /nix /ppm /style /incident` load topic-relevant domain packs on demand.)*

This document is the authoritative source for rules every agent follows, regardless of role, repo, or operator profile. Other layers (read top-down for full context):

- **[AGENTS-CORE.md](./AGENTS-CORE.md)** — universal rules every agent follows
- **an operator profile** — personal preferences of whoever runs the fleet. Not
  published here; each operator supplies their own private layer.
- **AGENTS-AGENT-*.md** — per-role overlays (one per agent identity)
- **per-repo AGENTS.md** — repo-specific deltas

---

## Topic: security/design

- 🟡 **STRONG** | `prefer` | When an app has too much privilege via its credential, prefer to constrain the credential at env boundary rather than add defensive checks in app code


## Topic: security/destructive-ops

- 🔴 **HARD** | `always` | Agent ships reversible changes without asking; pauses and explicitly asks before destructive ops (--rekey, nixos-rebuild switch on critical services, secret material)

- 🔴 **HARD** | `never` | Destructive git ops (reset --hard, clean, restore, rm) forbidden unless explicitly permitted

- 🔴 **HARD** | `never` | Do not delete or rename unexpected items; stop and ask

- 🟡 **STRONG** | `always` | For any infra change touching auth, keep a live root/sudo session open as a recovery channel throughout the change — use it only for recovery, not for the change


## Topic: security/encrypted-files

- 🔴 **HARD** | `never` | Never touch .age or .env files without explicit permission

- 🔴 **HARD** | `do` | Provide commands for the user to run themselves (e.g. agenix -e secrets/<name>.age) — do not run them

- 🔴 **HARD** | `always` | To modify encrypted content: ASK ('I'll need to decrypt. Should I proceed?'), GUIDE (provide commands for user to run), VERIFY (file size before/after), NEVER assume permission

- 🔴 **HARD** | `always` | When user wants to modify encrypted content, ask permission before decrypting

- 🟡 **STRONG** | `do` | Check encrypted file size before/after edit (encrypted file is typically 5KB+)


## Topic: security/git-commits

- 🔴 **HARD** | `always` | AI duty: detect potential secret -> STOP -> alert user -> suggest env var -> wait for confirmation

- 🔴 **HARD** | `always` | Always scan git diff for secrets before committing.

- 🔴 **HARD** | `always` | Before every commit: git diff to scan for secrets, git status to verify files

- 🔴 **HARD** | `never` | Never commit secrets: plain text passwords, API keys, tokens, bcrypt hashes, .env files with real credentials


## Topic: security/secrets-output

- 🔴 **HARD** | `always` | Any script that prints secrets to stdout MUST default to redacted (e.g. <redacted, length=N>); cleartext via opt-in only (e.g. --print-secret)

- 🔴 **HARD** | `always` | Apply the principle (any command whose output IS the resolved environment is forbidden), not the literal list — list will never be exhaustive

- 🔴 **HARD** | `avoid` | Avoid any command where secret values could appear in stdout or stderr.

- 🔴 **HARD** | `always` | Before EVERY Bash command, mentally check: could stdout/stderr contain secrets? does it touch the agent-secrets directory, ~/.ssh/, /run/agenix/, *.env, *.age? does it involve env/printenv/set/export/declare/direnv export/source/cat/head/tail?

- 🔴 **HARD** | `do` | Before every Bash command, ask: could this command stdout/stderr contain a secret value?

- 🔴 **HARD** | `do` | Before every Bash command, check whether it touches ~/Secrets/, the agent-secrets directory, ~/.ssh/<not-pub>, /run/agenix/, .env, .age or .gpg paths

- 🔴 **HARD** | `always` | Bootstrap scripts that write secrets to .env MUST default to <redacted, length=N> in stdout; cleartext via opt-in only (e.g. --print-secret)

- 🔴 **HARD** | `never` | Do not assume 'just this once is fine' for secret exposure; there is no fine

- 🔴 **HARD** | `never` | Do not copy the secret file to a different location to 'stage' it for use

- 🔴 **HARD** | `never` | Do not decrypt-and-display, base64-decode-and-display, or otherwise transform-then-display secret values

- 🔴 **HARD** | `never` | Do not remove a filter from a command that returned empty and re-run unfiltered; diagnose the underlying state instead

- 🔴 **HARD** | `never` | Do not run commands whose output is the resolved environment (direnv export, set, declare -x, declare -p, compgen -e, export -p, docker exec cat env, kubectl get secret -o yaml)

- 🔴 **HARD** | `always` | For secret-pipeline verification, use only safe primitives: ls|wc -l (count), [ -n $VAR ] && echo set (presence), error-count grep, file (content sniff) — never echo $VAR

- 🔴 **HARD** | `never` | If a filtered command returns empty unexpectedly, do NOT remove the filter and re-run — diagnose the underlying state; the filter was probably correct

- 🔴 **HARD** | `never` | NEVER use sed/head/cat on files in ~/Secrets/ even with truncation intent — partial-key leaks slip through

- 🔴 **HARD** | `never` | Never apply text manipulation (sed/head/cat/cut) to anything in ~/Secrets/ — partial-key leaks slip through (e.g. sed-truncating leaked partial PPM API key)

- 🔴 **HARD** | `never` | Never cat, head, tail, less, more, bat, xxd, od, or any other tool that prints contents of files in ~/.inspr/secrets/agents/

- 🔴 **HARD** | `never` | Never dump container or process environment unfiltered — avoid `docker inspect`, `ps auxe`, and `kubectl describe`/`env`-style commands that may expand secrets in their output; if env inspection is required, filter to keys-only or scrub values first. Canonical incident: re-send-from-PPM leak.

- 🔴 **HARD** | `never` | Never include the secret value in any tool output, chat message, commit, log, or file the user might later open

- 🔴 **HARD** | `never` | Never pass the secret value as a literal command-line argument (visible in ps, shell history, audit logs)

- 🔴 **HARD** | `never` | Never pipe a secret-bearing file into a downstream-visible position (e.g. source <env-file>; env, agenix -d <file>.age to stdout)

- 🔴 **HARD** | `never` | Never put secrets, API tokens, or credentials in ticket descriptions or notes; they stay in agenix

- 🔴 **HARD** | `never` | Never read, cat, or print the secrets file; source it and use the variables instead.

- 🔴 **HARD** | `never` | Never read, cat, print, head, tail, echo, or source secret files to stdout.

- 🔴 **HARD** | `never` | Never read, cat, print, or source secret/env files like ~/Secrets/*, .env*, .age, /run/secrets/* — direnv loads the env var.

- 🔴 **HARD** | `never` | Never run `direnv export <shell>` — it emits resolved env values to stdout

- 🔴 **HARD** | `never` | Never run `direnv status` when active — may leak a subset of secrets

- 🔴 **HARD** | `never` | Never run `env` or `printenv` without naming a specific non-sensitive variable

- 🔴 **HARD** | `never` | Never run cat/less/head/tail/bat/xxd/od/hexdump/strings on .env, .age, .gpg, .enc, .key, id_*, *_rsa, *_ed25519 or any file under the agent-secrets directory, ~/Secrets/, /run/agenix/, /run/secrets/

- 🔴 **HARD** | `never` | Never run cat/less/head/tail/echo on .env, .age, .gpg, /run/secrets/*, /run/agenix/* files

- 🔴 **HARD** | `never` | Never run commands that could print secrets to stdout or stderr.

- 🔴 **HARD** | `never` | Never run direnv export, direnv status, set, declare -x/-p, compgen -e, export -p, or container/k8s 'resolved' config peeks — they emit resolved environment with secret values

- 🔴 **HARD** | `never` | Never run docker exec ... cat /home/node/.env or any container env file

- 🔴 **HARD** | `never` | Never run printenv, env, or export without explicit filtering

- 🔴 **HARD** | `never` | Never run set, declare -x/-p, compgen -e, or export -p — they print env values

- 🔴 **HARD** | `never` | Never use docker exec cat /home/node/.env, kubectl get secret -o yaml or describe configmap after env expansion — work from the git source file with placeholders intact

- 🔴 **HARD** | `never` | Never use sed/head/cat on files in ~/Secrets/ even with truncation intent; partial-key leak via sed truncation is real

- 🔴 **HARD** | `never` | Never use the Read tool on env-file secrets in ~/.inspr/secrets/agents/

- 🔴 **HARD** | `never` | Secrets must never appear in stdout, stderr, or any tool output captured by the agent harness

- 🔴 **HARD** | `do` | To verify a secret exists, use ls -la only; never print the value

- 🔴 **HARD** | `never` | Treat ~/Secrets/*, .env, .env.local, .age, .gpg, /run/secrets/*, /run/agenix/* as secret files; never output their contents.

- 🟡 **STRONG** | `always` | Any glob + source/exec/eval loop needs an invariant check on each iteration (content type, file size, magic bytes); or each file's type should be visible from name without inspection

- 🟡 **STRONG** | `never` | Extensions encode content type — don't reuse one extension across types unless every consumer is type-aware (e.g. .env for both env vars and SSH keys cost a leak)

- 🟡 **STRONG** | `do` | Verify a secret exists with test -n "$VAR"; never print the value.


## Topic: security/ssh-keys

- 🔴 **HARD** | `always` | For trust-modifying infra rollouts, design new mechanism to be ADDITIVE alongside the old one; never remove a key during rollout, only add — prevents lockout

- 🔴 **HARD** | `never` | Never read any ~/.ssh/ file lacking the .pub extension

- 🔴 **HARD** | `always` | command='...'-restricted SSH keys MUST be preserved verbatim through any keyring abstraction (extraKeys raw-passthrough); abstracting strips restrictions and degrades security


## Topic: incident-response/secret-leak

- 🔴 **HARD** | `always` | If a workflow seems to require seeing a secret value (vs using it via env-loaded process), stop and ask the user

- 🔴 **HARD** | `always` | If encrypted file corrupted: STOP, alert user, guide restore from git, rotate credential

- 🔴 **HARD** | `always` | If secrets appear in output, STOP — do not run further commands that could touch the same secret pipeline

- 🔴 **HARD** | `always` | If secrets appear in tool output: STOP, do not reference, repeat, or quote the values; inform user immediately

- 🔴 **HARD** | `always` | If secrets committed: STOP, tell user immediately, discuss, rotate credential; if pushed assume compromised

- 🔴 **HARD** | `always` | On secret leak, name the affected variables to the user but never the values

- 🔴 **HARD** | `always` | Rotate any secret that appeared in full in transcripts; treat transcripts as leaked-by-default if they ever left the local machine (sent to cloud, shared, uploaded), and prefer immediate rotation over containment.

- 🔴 **HARD** | `always` | Rotate every exposed credential before continuing after a leak


## Topic: secrets/access-pattern

- 🔴 **HARD** | `never` | Source an agent env-file via `set -a; source <agent-secrets-dir>/<NAME>.env; set +a`; never cat or read the file

- 🔴 **HARD** | `do` | Use secrets indirectly by sourcing the env file into a subshell environment for a specific command (set -a; source FILE; set +a; cmd)

- 🟡 **STRONG** | `prefer` | Name materialized env files after the consumer tool's documented env-var convention (e.g. GH_TOKEN.env) so consumer defaults pick up automatically



- 🟡 **STRONG** | `do` | Store agent secrets one-per-file in a dedicated agent-secrets directory, naming each file after the env var it exports, so the filename is the variable name. The concrete path is set by the private kernel.


## Topic: secrets/agenix-pipeline

- 🔴 **HARD** | `never` | Never run `just rekey` — that command is user-only

- 🔴 **HARD** | `always` | Pipeline order is ALWAYS declare → encrypt → commit; agenix -e requires the file path declared in secrets/secrets.nix first or errors with 'attribute missing'

- 🔴 **HARD** | `always` | Sequence for AGE recipient rotation: add new recipient → agenix --rekey → verify decryption with new key → only THEN remove old recipient → agenix --rekey again

- 🟡 **STRONG** | `always` | On every macOS host that becomes an agenix recipient, manually generate a dedicated /etc/ssh/ssh_host_ed25519_key with ssh-keygen as agenix identity anchor


## Topic: style/communication

- 🟡 **STRONG** | `do` | Search the web early; never guess or invent URLs; quote exact errors; prefer 2026+ sources, fallback older

- 🟡 **STRONG** | `always` | When reporting 'no manual intervention needed', verify with the user before claiming it; the agent's tool view may not reflect actual screen state


## Topic: style/file-operations

- 🟡 **STRONG** | `never` | No repo-wide search/replace scripts; keep edits small and reviewable

- 🟡 **STRONG** | `always` | Use rsync --checksum reflexively for any file that 'should have changed but didn't seem to' — default mtime+size check sometimes skips changed files

- 🟢 SOFT | `prefer` | On macOS, /etc/ssh/*.pub is world-readable — read pubkeys via plain cat, not sudo, to avoid Touch ID friction


## Topic: style/markdown-policy

- 🔴 **HARD** | `never` | Never create new .md files unless user explicitly requests it

- 🟡 **STRONG** | `do` | If tempted to create a new markdown file, ask first which existing doc to update

- 🟡 **STRONG** | `prefer` | Prefer editing existing docs over creating new ones

- 🟡 **STRONG** | `never` | When a path is host-specific, NEVER hardcode it into shared-repo docs — even one that looks 'obviously stale'; unify via source-of-truth materialization layer first

- 🟡 **STRONG** | `do` | When asked to "document X": update README.md or RUNBOOK.md, do not create a new file


## Topic: tools/agenix

- 🔴 **HARD** | `always` | For multi-isolation-island repos, pass MULTIPLE -i flags to agenix --rekey covering every operator key; rekey is all-or-nothing and aborts on first error

- 🔴 **HARD** | `never` | Never touch .age files without explicit permission (agenix doctrine)

- 🔴 **HARD** | `always` | When invoking agenix non-interactively, pipe content via stdin — never a plaintext file; on macOS with nix coreutils run `PATH=/bin:$PATH agenix -e dest.age < src`: agenix hard-codes `cp -- /dev/stdin`, and GNU cp 9.x refuses it ("replaced while being copied") for pipes and redirects alike, so the file is not created; historical `EDITOR='cp $src'` silently encrypted 0 bytes and stays forbidden

- 🟡 **STRONG** | `always` | Always verify with git status + size comparison after agenix --rekey before assuming destructive failure; agenix's atomic-write safety prevents in-place corruption

- 🟡 **STRONG** | `always` | Rekey verification needs decryption-with-the-NEW-identity, not just successful rekey exit code (which can mean 'kept old recipients and added nothing')


## Topic: tools/bootstrap-scripts

- 🟡 **STRONG** | `always` | Bootstrap scripts that manage multiple secrets in .env should use per-key boolean pairs (WRITE_X + ROTATE_X), NOT a single --write-env flag that rotates all

- 🟡 **STRONG** | `prefer` | For self-hostable systems with non-obvious init traps, maintain ONE executable bootstrap as canonical state spec; resist splitting into script + troubleshooting markdown


## Topic: tools/gh

- 🟡 **STRONG** | `do` | In PR replies cite fix and file/line; resolve threads only after the fix lands

- 🟡 **STRONG** | `prefer` | Use gh pr view/diff for PRs (not URLs)


## Topic: tools/inspr-doctor

- 🟡 **STRONG** | `prefer` | For security-restricted dirs probe what unprivileged code can actually prove ([ -d $dir ]); don't try to inspect what's intentionally hidden


## Topic: tools/just

- 🟡 **STRONG** | `always` | In just recipe docstrings, show invocations with positional args only — never name=value syntax which is parsed as a literal string passed to first positional arg


## Topic: tools/script-design

- 🔴 **HARD** | `always` | Every script that touches a remote auth system should default to read-only/preserve and require explicit opt-in for any state change

- 🟡 **STRONG** | `always` | In auto-detect heuristics that depend on tool presence, normalize the environment (PATH export) BEFORE probing it with command -v

- 🟡 **STRONG** | `always` | When sed-renaming functions across a known set, ALWAYS use comm(1) over BOTH function-name lists to find the FULL collision set BEFORE writing the rename loop — don't iterate


## Topic: tools/shell-quoting

- 🟡 **STRONG** | `avoid` | Avoid English-contraction apostrophes in awk/shell embedded in single-quoted strings (Nix-rendered or otherwise) — they prematurely terminate the quoted region


## Topic: tools/ssh

- 🟡 **STRONG** | `always` | For local-user scope in ssh_config Match use LocalUser (or LocalHost / OriginalHost); bare User/Host describe TARGET, not ORIGIN

- 🟡 **STRONG** | `always` | In ssh_config Match, use LocalUser/LocalHost/OriginalHost for origin-scoping; bare User/Host describe the connection TARGET, not the local user running ssh



## Topic: tools/trash

- 🔴 **HARD** | `never` | For deletes use trash, never rm -rf


## Topic: process/build-test

- 🟡 **STRONG** | `do` | Keep notes short; update docs when behavior or API changes (no ship without docs)

- 🟡 **STRONG** | `do` | On CI red: gh run list/view, rerun, fix, push, repeat to green

- 🟡 **STRONG** | `do` | Use the repo package manager and runtime; no swaps without approval


## Topic: process/config-management

- 🟡 **STRONG** | `always` | For any tool with both legacy non-XDG and XDG config locations, declarative config managers should warn loudly when both files exist on the same host


## Topic: process/critical-thinking

- 🔴 **HARD** | `always` | Always verify the full context of edits; read before replacing

- 🔴 **HARD** | `do` | Clarity over speed: if uncertain, ask before proceeding; better one question than three bugs

- 🔴 **HARD** | `always` | When automation seems stuck, investigate via systemctl status + journalctl BEFORE force-killing; operator-induced fix attempts often cause more damage than the original problem

- 🟡 **STRONG** | `always` | Always verify post-action (git status, ls -la, decrypt-test, etc.); the verification step is part of the operation, not optional cleanup

- 🟡 **STRONG** | `always` | Automation patterns that work interactively can fail silently in non-interactive contexts — always verify outputs structurally (size, content sniff), not just by exit code

- 🟡 **STRONG** | `always` | Before assuming an infrastructure surprise is a real bug, gather concrete journal evidence (timestamps, systemd state transitions, operator commands intervened)

- 🟡 **STRONG** | `dont` | Don't guess or invent URLs; quote exact errors

- 🟡 **STRONG** | `do` | Fix root cause, not band-aid

- 🟡 **STRONG** | `do` | Follow links until domain makes sense; honor existing patterns

- 🟡 **STRONG** | `always` | Institutional advice from a vendor optimizes for the vendor's preferred shape — useful signal, not authoritative; re-derive against own axes (portability, rotation, scope) before adopting

- 🟡 **STRONG** | `do` | On conflicts, call them out and pick the safer path

- 🟡 **STRONG** | `always` | Re-survey existing tooling on --help before scoping any 'extend X' ticket; periodic ticket reality-check is its own backlog hygiene activity

- 🟡 **STRONG** | `always` | When framing 'smaller=safer vs bigger=right', verify the bigger option is actually feasible TODAY (research blockers/issues); defer because of brittleness, not size

- 🟡 **STRONG** | `always` | When integrating against unfamiliar API surface — especially across version-spans — always probe actual endpoint behavior before designing the idempotency strategy

- 🟡 **STRONG** | `prefer` | When joining an existing repo with its own pattern, prefer hybrid coexistence + a follow-up ticket over unilateral refactor that touches production-prod code

- 🟡 **STRONG** | `do` | When unsure read more code; if still stuck ask with short option list

- 🟢 SOFT | `do` | Treat unrecognized changes as another agents work; keep going on your scope and stop+ask only on issues


## Topic: process/design-doctrine

- 🟡 **STRONG** | `prefer` | For stable infrastructure credentials, prefer primitives that NEVER rotate (deploy keys, classic PATs) or auto-rotate invisibly (App tokens, OIDC); manual rotation only where rotation is the point

- 🟡 **STRONG** | `always` | When a design decision goes through many reorientations, capture the trail (what was tried/rejected and why) so alternatives don't get re-litigated every session

- 🟡 **STRONG** | `always` | When designing for a fleet, draw the 'who owns this identity?' question explicitly — human vs machine; the answer rules out half the credential primitives immediately

- 🟡 **STRONG** | `always` | When picking a credential primitive, first ask 'is this identity owned by a human or by a machine?' — the answer rules out half the options immediately


## Topic: process/host-recovery

- 🟡 **STRONG** | `always` | SSH-back is necessary but not sufficient post-reboot; build a routine that waits for SSH + ICMP + expected systemd targets active + expected container count


## Topic: process/migrations

- 🟡 **STRONG** | `always` | For declarative-replaces-imperative file migration: backup → activate → verify → strip the unmanaged region; trade off in favor of redundancy over potential lockout


## Topic: process/onboarding

- 🟡 **STRONG** | `always` | Onboarding tooling must always distinguish host and service URL explicitly in any setup form; never let one default-fill into the other

- 🟡 **STRONG** | `always` | Probe responses should be validated by examining body and headers, not just the status code; healthchecks must assert on response content

- 🟡 **STRONG** | `prefer` | Test URLs by probing for protocol-shaped responses (e.g. Tailscale-shaped JSON), not merely 'HTTPS works' or HTTP status code


## Topic: process/pre-commit-checklist

- 🔴 **HARD** | `always` | Run mental pre-flight before every Bash command in secret-adjacent context: could stdout/stderr contain a secret, does it touch secret paths, does it involve env-printing tools, did a filtered command return empty

- 🟡 **STRONG** | `always` | After shipping anything claimed-as-done, do a structured C/H/M/O severity pass through the artifacts asking 'would this withstand a tough security and validity audit?'

- 🟡 **STRONG** | `do` | Before handoff, run the full gate: lint, typecheck, tests, docs


## Topic: process/rollout-discipline

- 🟡 **STRONG** | `prefer` | For prod-adjacent first cutovers use 1 step = 1 commit = 1 validation gate; once pattern is proven, subsequent hosts can absorb same N changes as one atomic commit


## Topic: process/sync-triad

- 🔴 **HARD** | `always` | Prime Directive: keep config, docs, and tests in sync


## Topic: workflow/work-attribution

- 🔴 **HARD** | `always` | Before material work, bind the exact user-authorized scope to one existing ticket in the product's designated PPM or PMA tracker; never split or duplicate the same work across both trackers. If no suitable ticket exists, create it before any edit, commit, deployment, external write, or other state-changing action. Read-only orientation and status inspection are not material work.

- 🔴 **HARD** | `always` | When a worker cannot write the designated tracker, its coordinating session MUST create or reuse the ticket and add the worker marker before dispatch. The worker does not substitute a local backlog note or start untracked; no marker means no material work.

- 🔴 **HARD** | `always` | Before material work starts, record every participating agent or subagent on that ticket as `I work on this — session: <session-name> (<session-UUID>); role: <builder|reviewer|operator>; started: <ISO-8601>`. Do not name only the coordinator when a child implements.

- 🔴 **HARD** | `always` | Preserve attribution history: add a new marker when ownership transfers or a reviewer/operator joins; never overwrite an earlier marker. One implementer per ticket is the default. Parallel builders require explicit, non-overlapping child-ticket scopes.

- 🔴 **HARD** | `never` | A work marker must not contain credentials, secrets, private prompts, raw payloads, or unrelated personal data, and it never means accepted, approved, merged, or exclusively owned beyond the declared role.

## Topic: workflow/ppm

- 🔴 **HARD** | `do` | Mark PPM tickets as done only when acceptance criteria are met.

- 🟡 **STRONG** | `always` | Always reference PPM tickets by human-visible key (e.g. FLEET-79) in chat, commits, branches, PR titles; numeric DB id is for API calls only.

- 🔴 **HARD** | `do` | Apply the universal ticket-first and session-attribution protocol in `workflow/work-attribution`; use the owning product's designated tracker and do not create a second copy merely to satisfy a preferred tracker.

- 🟡 **STRONG** | `dont` | Do not create local backlog files. When PPM writes are explicitly authorized, create epics and tickets in PPM instead.

- 🟡 **STRONG** | `do` | When PPM writes are explicitly authorized, update ticket status as work progresses (new -> backlog -> in-progress -> qa -> done); use post-delivery states separately.

- 🔴 **HARD** | `never` | Never start a tracker time entry. Agents do not time-track; stop only an entry you started yourself, and leave anyone else's alone — a running entry usually means another live session.
- 🟡 **STRONG** | `do` | When tracker writes are explicitly authorized and work is done, update the ticket status.


## Topic: pacing/long-running

- 🟡 **STRONG** | `do` | Background or zellij session for long jobs

- 🟡 **STRONG** | `do` | Prefix long-running commands (>10s) with date && (bash) or date; and (fish) for timestamping


## Topic: git/identity

- 🔴 **HARD** | `never` | Never invent identity values (placeholder emails, names, etc.) — ask the user or fail loudly; placeholders end up permanent in commit metadata

- 🔴 **HARD** | `never` | Never invent placeholder identity values like user@example.com or name@placeholder.local; if tempted to fabricate one, stop and ask the user or fail loudly

- 🟡 **STRONG** | `always` | Any tool auto-generating includeIf hasconfig:remote.*.url rules must produce paired HTTPS-anchored AND SSH-anchored patterns since * does not cross URL component boundaries

- 🟡 **STRONG** | `prefer` | Prefer content-derived rules (e.g. hasconfig:remote.*.url) over enumeration-based rules (gitdir lists) whenever the underlying truth is queryable


## Topic: git/safety

- 🔴 **HARD** | `never` | If pre-commit hooks modify files, stage them and create a fresh commit attempt; never amend

- 🔴 **HARD** | `never` | Never run `git push --force` without explicit user request

- 🔴 **HARD** | `never` | No amend unless asked

- 🔴 **HARD** | `always` | On the `/push` slash command: proceed without asking confirmation, but STOP and alert the user if the diff or working tree shows potential secrets or unexpected files before any push happens.

- 🟡 **STRONG** | `do` | After commits succeed, run `git pull --rebase && git push`

- 🟡 **STRONG** | `always` | Always re-git-add edited files before commit, or use git commit -a for tracked files; the AM letter combination warns of stale staged versions

- 🟡 **STRONG** | `do` | Branch changes require user consent

- 🟡 **STRONG** | `do` | Group changes into logical commits; do not lump unrelated changes into one commit

- 🟡 **STRONG** | `do` | Multi-agent: check git status/diff before edits; ship small commits

- 🟡 **STRONG** | `do` | On /push, commit and push the current working directory repo only

- 🟡 **STRONG** | `do` | Use the repo existing commit message style (check git log --oneline -10)

- 🟢 SOFT | `do` | For big review use git --no-pager diff --color=never


## Topic: nix/flakes

- 🟡 **STRONG** | `always` | Automation must git add -N (intent-to-add) any files it generates BEFORE running flake operations because flakes only see git-tracked files


## Topic: nix/modules

- 🟡 **STRONG** | `always` | Any derivation that programmatically transforms an externally-versioned input MUST include sanity asserts on output (positive markers + inverse checks) — cheap insurance against upstream drift

- 🟡 **STRONG** | `prefer` | At module design time, default to multi-user shapes (users.<name>.{trust,...}) over single-user — costs nothing for common case, prevents future breaking refactor

- 🟡 **STRONG** | `always` | Build-time sanity asserts in pkgs.runCommand derivations are cheap insurance against upstream API drift — positive checks (markers present) + inverse checks (no old marker remaining)

- 🟡 **STRONG** | `always` | For HM-on-NixOS modules consuming flake inputs, always import upstream HM modules at the NixOS-scope wire-up site, never in HM-side files (unless extraSpecialArgs is wired)

- 🟡 **STRONG** | `always` | For system-wide ssh CLIENT config (Match blocks, IdentityFile pinning), always use programs.ssh.extraConfig; never rely on /etc/ssh/ssh_config.d/ glob-include — verify with ssh -v

- 🟡 **STRONG** | `prefer` | In Nix, validation throws must be on a path that's guaranteed-evaluated; lazy-bound let _ = X doesn't count — use builtins.seq or move into config.assertions

- 🟡 **STRONG** | `always` | NixOS programs.ssh client side does NOT include /etc/ssh/ssh_config.d/*.conf; always use programs.ssh.extraConfig for system-wide ssh-client Match blocks

- 🟡 **STRONG** | `always` | builtins.readDir patterns should warn or fail loudly when they discover zero files in a directory the user clearly intended to use

- 🟢 SOFT | `prefer` | NixOS git build reads /etc/gitconfig by default; environment.etc.gitconfig.text works for system-wide url.insteadOf without needing /root/.gitconfig


## Topic: nix/strings

- 🟡 **STRONG** | `avoid` | Treat all text inside Nix '' multiline strings as Nix tokens including # comments; prefer pkgs.writeShellApplication store paths to embedded heredocs


## Topic: nix/syntax

- 🟡 **STRONG** | `prefer` | Nix or keyword only works in attrs.attr or default form — NOT as binary infix; reach for explicit if over clever or when in doubt


## Topic: nixos/activation

- 🔴 **HARD** | `always` | Always run nix profile list on a macOS host BEFORE home-manager switch if there's any chance of imperative installs; resolve conflicts FIRST to avoid bricked profile

- 🔴 **HARD** | `always` | On HM/NixOS activation failure, verify (a) login shell still execable, (b) PATH binaries present, (c) SSH still functional, (d) home-manager itself still in profile

- 🟡 **STRONG** | `always` | Activation scripts that create immutable artifacts must remove-then-recreate, not overwrite-in-place; locked file modes block subsequent rewrites

- 🟡 **STRONG** | `always` | After HM activation failure, verify the file you came to change is actually changed before declaring victory; early-step failure can silently bypass later steps

- 🟡 **STRONG** | `always` | In HM activation DAGs, treat umask (and process-state mutables like cd, set -e) as something predecessors may have modified — always reset to expected value at top of script

- 🟡 **STRONG** | `always` | In HM activation scripts, treat PATH as minimal-coreutils; either reference system tools by absolute path (/usr/bin/awk) or use bash builtins

- 🟡 **STRONG** | `always` | In activation scripts that create protective directories, open the dir with write perms first, do all writes, lock to restrictive mode last

- 🟡 **STRONG** | `always` | When mixing package-manager-installed binaries with Nix-managed wrappers, the activation DAG must explicitly sequence install → wrap (entryAfter); implicit ordering doesn't work


## Topic: nixos/build-safety

- 🔴 **HARD** | `never` | Never systemctl stop nixos-rebuild-switch-to-configuration.service on the 'already loaded' error; wait for is-active inactive or use systemctl reset-failed

- 🟡 **STRONG** | `prefer` | Before nixos-rebuild test/switch on a host you haven't recently rebooted, check for staged-kernel state; if pending prefer nixos-rebuild boot + scheduled reboot

- 🟡 **STRONG** | `prefer` | For generic glibc binaries failing on NixOS with 'no such file' on existing executable, enable programs.nix-ld — fixes whole class of binaries vs steam-run/patchelf for one

- 🟡 **STRONG** | `avoid` | With NixOS users.mutableUsers=true (default), hashedPassword is only consumed at INITIAL user creation; subsequent rebuilds don't propagate — use hashedPasswordFile instead

- 🟢 SOFT | `prefer` | When pulling on remote host before nixos-rebuild, distinguish flake-relevant files (.nix, flake.lock, imports) from incidental files; only the former block deployment


## Topic: nixos/debugging

- 🟡 **STRONG** | `prefer` | When a module test fails opaquely, drop the harness and call lib.evalModules directly on a minimal stub to see the raw config tree — splits module-vs-harness bugs

- 🟡 **STRONG** | `prefer` | When nix flake check fails with confusing trace, don't chase the trace at face value — bisect by evaluating each top-level output category in isolation


## Topic: infra/tailscale

- 🔴 **HARD** | `never` | Tailscale --login-server must point at the service URL (e.g. your Headscale service URL), never the container host hostname

- 🟡 **STRONG** | `always` | Any tailscale up automation must always pass --login-server explicitly because macOS Tailscale daemon prefs do not reliably survive reboot

- 🟡 **STRONG** | `never` | Do not sudo the macOS Tailscale CLI; daemon runs as root via system extension and CLI talks via Unix socket as the regular user

<!--
  Note: the `agent-protocol/session-startup` topic added 2026-05-15 morning
  (INSPR-190 transitional startup-hint, tagged sunset 2026-06-15) was
  REMOVED later the same day by INSPR-189 Phase 6. The kernel
  (AGENTS-KERNEL.md) router supersedes that transitional hint.
-->
