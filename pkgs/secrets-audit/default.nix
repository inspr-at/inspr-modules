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
# So the canonical install pattern is: `secrets-audit` from anywhere in or
# adjacent to a nixcfg checkout.
#
{
  lib,
  stdenv,
  bash,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  git,
  jq,
}:

stdenv.mkDerivation {
  pname = "secrets-audit";
  version = "0.1.0";

  src = ./.;

  buildInputs = [ bash ];

  installPhase = ''
    install -Dm755 secrets-audit.sh $out/bin/secrets-audit
  '';

  # Patch the shebang to use the bash from this derivation, and ensure
  # all coreutils/grep/sed/jq binaries the script calls resolve via the
  # store rather than relying on a particular system PATH.
  postFixup = ''
    substituteInPlace $out/bin/secrets-audit \
      --replace "#!/usr/bin/env bash" "#!${bash}/bin/bash"
    wrapProgram() { :; }  # noop placeholder; we PATH-prefix instead
    # Prepend a known PATH so subshell-spawned tools resolve correctly
    sed -i '2i export PATH="${
      lib.makeBinPath [
        coreutils
        findutils
        gnugrep
        gnused
        git
        jq
      ]
    }:$PATH"' $out/bin/secrets-audit
  '';

  meta = with lib; {
    description = "Audit drift between secrets/*.age and secrets.nix declarations";
    homepage = "https://github.com/markus-barta/inspr-modules";
    license = licenses.mit;
    mainProgram = "secrets-audit";
    platforms = platforms.unix;
  };
}
