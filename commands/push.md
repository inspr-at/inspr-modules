Commit all uncommitted changes in the **current working directory repo** and push to remote. Follow this procedure:

1. Run `git status` + `git diff` (staged + unstaged) to see everything that changed.
2. **Group changes into logical commits** — files that belong together (same feature, same host, same fix) go in one commit. Don't lump unrelated changes into a single commit. Examples:
   - All files for one host change → one commit
   - A docs update → separate commit
   - A script change unrelated to config → separate commit
   - Formatting / lint fixes → separate commit
3. For each group: `git add <files>` then `git commit -m "<message>"`. Use the repo's existing commit message style (`git log --oneline -10`).
4. If pre-commit hooks modify files (shfmt, prettier, etc.): stage the auto-fixed files and retry the commit. **Never `--amend`** — create a fresh commit attempt.
5. After all commits succeed: `git pull --rebase && git push`.
6. If changes should NOT be pushed together (e.g., risky vs safe), do multiple push rounds — push safe commits first, then the rest.
7. Run `git status` at the end to confirm clean working tree.

Do NOT ask for confirmation — just do it. If something looks wrong (secrets, unexpected files), STOP and alert the user.
