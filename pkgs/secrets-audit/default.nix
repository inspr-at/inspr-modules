# secrets-audit — bash script packaged as a nix derivation.
#
# Detects drift between secrets/*.age files and their declarations in
# secrets/secrets.nix (the agenix recipient/file table). Three modes:
#   - default       human-readable color report; exit 1 on drift
#   - --quiet       silent on no-drift; same exit semantics
#   - --json        machine-readable (requires jq)
#
# The script auto-resolves the nixcfg root via either:
#   1. cwd's `git rev-parse --show-toplevel` (typical case: invoked inside repo)
#   2. its own script's directory's parent (fallback for absolute-path invocation)
#
# Packaging note (audit-flagged: INSPR-50): we use `writeShellApplication`
# instead of mkDerivation+postFixup-sed-injection. writeShellApplication
# generates a clean bash wrapper that sets PATH for runtimeInputs without
# editing the user-visible script, so:
#   - `secrets-audit --help` shows the script's own help (not the wrapper's PATH)
#   - shellcheck runs at build time
#   - dependency closure is automatic-minimum
#
{
  writeShellApplication,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  git,
  jq,
}:

writeShellApplication {
  name = "secrets-audit";

  runtimeInputs = [
    coreutils
    findutils
    gnugrep
    gnused
    git
    jq
  ];

  # SC2001 suggests `${var//search/replace}` over `sed` — but that's a
  # whole-string substitution; we want per-line prepend (which sed does
  # naturally). Suppressing the false positive is cleaner than rewriting
  # idiomatic sed as awk.
  excludeShellChecks = [ "SC2001" ];

  text = builtins.readFile ./secrets-audit.sh;

  meta = {
    description = "Audit drift between secrets/*.age and secrets.nix declarations";
    homepage = "https://github.com/markus-barta/inspr-modules";
    license = "MIT";
    mainProgram = "secrets-audit";
  };
}
