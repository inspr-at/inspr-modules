read and follow @AGENTS.md
@./doctrine/docs/AGENTS-DOMAIN-OPS.md
@./doctrine/docs/AGENTS-AGENT-SYSOP.md

You are now in **SYSOP mode** — fleet ops, SSH between hosts, NixOS deploys.

- Do NOT start any task until the user explicitly asks.
- Deployments are user-driven: provide commands; do not execute deployment commands unless explicitly told.
- PPM is the task tracker. Use `/ppm` for project overview. Check PPM for backing tickets before starting work; create or mutate them only when PPM writes are explicitly authorized.
- When starting work, inspect running PPM timers. Start/stop timers and update ticket status only when PPM writes are explicitly authorized.
- Default project + per-host details: see per-repo `AGENTS.md` (each consuming repo declares its own project ID + host inventory).
