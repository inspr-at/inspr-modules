Commit and push across all workspace doctrine-vendoring repos. Process each repo in order:

1. `~/Code/inspr-modules` (upstream doctrine source — push first so submodule bumps downstream resolve)
2. `~/Code/nixcfg`
3. `~/Code/inspr`
4. `~/Code/fleetcom`

For each repo:

1. `cd` into the repo. If it doesn't exist, skip with a note.
2. Run `git status` — if clean and nothing to push, skip with a short note.
3. If there are changes, follow the **`/push` procedure**: group into logical commits, use repo's commit style, never `--amend`, `git pull --rebase && git push`.
4. If the doctrine submodule was bumped upstream, propagate downstream: `git submodule update --remote doctrine && git commit doctrine -m "doctrine: bump to <shortsha> (<reason>)"`.
5. If something looks wrong (secrets, unexpected files), STOP and alert the user — don't continue to other repos blindly.

After all repos are processed, print a **summary table**:

| Repo          | Status              |
| ------------- | ------------------- |
| inspr-modules | 1 commit pushed     |
| nixcfg        | submodule bump only |
| inspr         | clean, skipped      |
| fleetcom      | 2 commits pushed    |

Do NOT ask for confirmation between repos — just do it. Ask only if a STOP-worthy issue surfaces.

**Note on scope**: this `/pushall` covers the four doctrine-vendoring repos (where doctrine changes need to ripple). It does NOT push OpenClaw workspaces (`oc-workspace-*`) or other personal projects — those have their own ad-hoc push cadences. If you want to push everything in `~/Code/`, run `/push` per repo manually.
