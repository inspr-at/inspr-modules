{
  pkgs,
  skillSource,
  attributionSource,
  versioningSource,
}:

pkgs.runCommand "inspr-worker-doctrine" { } ''
  mkdir -p "$out/references"
  cp ${skillSource} "$out/SKILL.md"
  cp ${attributionSource} "$out/references/AGENTS.md"
  cp ${versioningSource} "$out/references/AGENTS-VERSIONING.md"
''
