{
  pkgs,
  skillSource,
  attributionSource,
  versioningSource,
  displaySource ? ./calendar-version-display.json,
}:

pkgs.runCommand "inspr-worker-doctrine" { } ''
  mkdir -p "$out/references"
  cp ${skillSource} "$out/SKILL.md"
  cp ${attributionSource} "$out/references/AGENTS.md"
  cp ${versioningSource} "$out/references/AGENTS-VERSIONING.md"
  cp ${displaySource} "$out/references/calendar-version-display.json"
''
