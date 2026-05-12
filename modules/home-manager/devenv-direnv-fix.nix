# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║      INSPR-175 — devenv direnv-lib function-name collision fix              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Declaratively materialize devenv's direnv-lib snippet
# (~/.config/direnv/lib/z-devenv.sh) with its colliding `_nix_direnv_preflight`
# function renamed to `_devenv_preflight`, so it no longer shadows nix-direnv's
# preflight when both libs are loaded by direnv.
#
# ── The bug (verified live on imac0, 2026-05-12) ────────────────────────
# direnv loads everything in `~/.config/direnv/lib/*.sh` alphabetically:
#   - hm-nix-direnv.sh (HM-managed, nix-direnv 3.1.1)
#       defines `_nix_direnv_preflight` that sets `_nix_direnv_nix=$(...)`.
#       The `_nix()` helper expands `${_nix_direnv_nix}` at call time.
#   - z-devenv.sh (devenv's own direnv extension, copied to user lib by
#     `devenv direnvrc > ~/.config/direnv/lib/z-devenv.sh` on first setup)
#       ALSO defines `_nix_direnv_preflight`, but ITS version sets
#       `DEVENV_BIN` and NEVER touches `_nix_direnv_nix`.
#
# Last definition wins — so devenv's broken version overrides nix-direnv's.
# When `.envrc` calls `use nix`:
#   1. direnv stdlib `use` dispatches to `use_nix` (from nix-direnv — devenv
#      doesn't redefine that one).
#   2. `use_nix` calls `_nix_direnv_preflight` — but this is now devenv's
#      version, which returns 0 WITHOUT setting `_nix_direnv_nix`.
#   3. Subsequent `_nix eval ...` expands to ` --no-warn-dirty ...` (leading
#      empty + space), bash interprets `--no-warn-dirty` as the command name.
#   4. Cryptic error: `hm-nix-direnv.sh:41: --no-warn-dirty: command not found`.
#
# ── The fix ─────────────────────────────────────────────────────────────
# Rename devenv's `_nix_direnv_preflight` to `_devenv_preflight` (and update
# its single internal caller). Both names are private; devenv only references
# the name via its own `use_devenv` function, which we rewire to the new name.
# nix-direnv's `_nix_direnv_preflight` survives unshadowed, `_nix_direnv_nix`
# gets set correctly, `use nix` and `use devenv` coexist.
#
# Source: `devenv direnvrc` subcommand (devenv's canonical embedded copy).
# We pull it at BUILD time and sed-rename, so the output auto-tracks devenv
# version bumps without manual re-patching. A build-time sanity check fails
# loudly if the rename produces no markers (catches upstream API drift —
# e.g., if devenv renames the function on its own, the build errors with a
# clear message rather than silently disabling the fix).
#
# ── Usage (consumer's home.nix) ─────────────────────────────────────────
#   imports = [ inputs.inspr-modules.homeManagerModules.devenv-direnv-fix ];
#   inspr.devenv.direnv-fix.enable = true;
#
# Consumer must have `devenv` in pkgs (the default is `pkgs.devenv`).
#
# ── Upstream status ─────────────────────────────────────────────────────
# This is a workaround. Proper fix belongs in devenv upstream (devenv should
# namespace its private functions as `_devenv_*`, not pretend to be
# nix-direnv). Filing upstream is INSPR-175 follow-up.
#
# License: MIT (part of inspr-modules — see flake.nix).
# ─────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.inspr.devenv.direnv-fix;

  # Build-time derivation: take devenv's canonical direnvrc, sed-rename ALL
  # function names that collide with nix-direnv, write to a store path.
  #
  # Three colliding functions (verified 2026-05-12 via diff against
  # nix-direnv 3.1.1's exported function set on imac0):
  #   - _nix_direnv_preflight  → renamed _devenv_preflight
  #     (the original collision; without this fix, `use nix` fails with
  #      `--no-warn-dirty: command not found` because `_nix_direnv_nix`
  #      is left empty)
  #   - _nix_import_env        → renamed _devenv_import_env
  #     (devenv's signature takes raw env content as $1; nix-direnv's
  #      takes a profile_rc PATH as $1. When devenv's shadows nix-direnv's,
  #      `use nix` fails with `<path>.rc: Permission denied` because the
  #      function tries to eval the file path as shell code rather than
  #      reading its contents.)
  #   - _nix_export_or_unset   → renamed _devenv_export_or_unset
  #     (functionally similar in both libs, but distinct enough that
  #      shadowing risks subtle bugs; rename for safety + symmetry)
  #
  # Devenv ALREADY namespaces some of its private functions correctly
  # (`_devenv_watches`, `use_devenv`) — these three are just oversights.
  # Filing upstream is the proper fix; this module is the workaround.
  #
  # Build-time sanity asserts catch upstream API drift: if any renamed
  # marker is missing OR any old `_nix_*` collision name remains in the
  # output, the build fails with a clear INSPR-175 message rather than
  # silently producing a still-broken file.
  patchedDirenvrc =
    pkgs.runCommand "z-devenv-patched.sh"
      {
        nativeBuildInputs = [ cfg.devenvPackage pkgs.gnused pkgs.gnugrep ];
      }
      ''
        ${cfg.devenvPackage}/bin/devenv direnvrc \
          | sed -e 's/_nix_direnv_preflight/_devenv_preflight/g' \
                -e 's/_nix_import_env/_devenv_import_env/g' \
                -e 's/_nix_export_or_unset/_devenv_export_or_unset/g' \
          > $out

        # Positive sanity: each renamed marker must be present.
        for marker in _devenv_preflight _devenv_import_env _devenv_export_or_unset ; do
          if ! grep -q "$marker" $out ; then
            echo "INSPR-175: ERROR — rename produced no '$marker' marker." >&2
            echo "  devenv direnvrc may have changed function names upstream." >&2
            echo "  Check the module + devenv direnvrc output." >&2
            exit 1
          fi
        done

        # Inverse sanity: no colliding _nix_* name should remain.
        for collision in _nix_direnv_preflight _nix_import_env _nix_export_or_unset ; do
          if grep -q "$collision" $out ; then
            echo "INSPR-175: ERROR — rename incomplete; '$collision' still present." >&2
            echo "  sed didn't catch all occurrences. Check the module." >&2
            exit 1
          fi
        done
      '';
in
{
  options.inspr.devenv.direnv-fix = {
    enable = lib.mkEnableOption ''
      INSPR-175 fix: declaratively materialize devenv's direnv-lib snippet
      with its `_nix_direnv_preflight` function renamed to `_devenv_preflight`,
      so it stops shadowing nix-direnv's preflight when both libs load. Both
      `use nix` and `use devenv` work after this is enabled
    '';

    devenvPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.devenv;
      defaultText = lib.literalExpression "pkgs.devenv";
      description = ''
        Devenv package used to source the canonical direnvrc. Override only
        if you're testing a specific devenv version.
      '';
    };

    targetPath = lib.mkOption {
      type = lib.types.str;
      default = ".config/direnv/lib/z-devenv.sh";
      description = ''
        Path inside `$HOME` where the patched direnvrc is materialized.
        Default matches direnv's lib-dir convention (filename prefix `z-`
        ensures alphabetical-load order puts it AFTER hm-nix-direnv.sh,
        same as the manual install — needed so nix-direnv defines the
        proper helpers first; rename of just `_nix_direnv_preflight` lets
        the rest of devenv's hooks coexist).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file.${cfg.targetPath}.source = patchedDirenvrc;
  };
}
