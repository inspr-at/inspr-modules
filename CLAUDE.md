<!--
  Layered doctrine loader for Claude Code sessions opened in inspr-modules itself.

  POST-PHASE-6 (INSPR-189, 2026-05-15):
  Auto-loaded doctrine = KERNEL only. Domain-specific rules load on demand
  via slash commands (/dev, /iac, /nix, /ops, /ppm, /secrets, /style, /incident).
  Kernel includes the slash-command router; run /inspr for the TL;DR map.

  Pre-Phase-6 sessions auto-loaded ~127k chars (CORE 64k + PROFILE-MARKUS 47k +
  per-repo AGENTS.md). Post-Phase-6 ≤10k chars in this repo (kernel only).
-->

@./docs/AGENTS-KERNEL.md
