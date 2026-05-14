<!--
  Layered doctrine loader for Claude Code sessions opened in this repo.

  Other tools (Cursor, OpenCode, Zed, Codex CLI, etc.) read AGENTS.md
  instead — but inspr-modules is the upstream doctrine source, so there's
  no per-repo thin overlay here. The canonical layered files are right
  next to this loader in ./docs/.

  This file makes Claude sessions opened in inspr-modules itself
  load the same layered context that consuming repos (nixcfg, fleetcom,
  inspr) load via their ./doctrine/ submodule pointing here.
-->

@./docs/AGENTS-CORE.md
@./docs/AGENTS-PROFILE-MARKUS.md
