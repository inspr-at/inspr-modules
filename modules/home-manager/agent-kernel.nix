# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              INSPR — Declarative kernel injection for CLI harnesses          ║
# ╚══════════════════════════════════════════════════════════════════════════════╗
#
# Materialize the public kernel (and optional extraSources, e.g. a studio
# private kernel) into each harness's global context file.
#
# Two install kinds:
#   - replace (default harnesses attrset): home.file, no force.
#   - marker (markerHarnesses): a bounded HTML-comment block inside an
#     existing user file so personal text survives.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.inspr.agent-kernel;

  payloadText = lib.concatStringsSep "\n\n" (
    [ (builtins.readFile cfg.source) ] ++ map builtins.readFile cfg.extraSources
  );

  payloadFile =
    if cfg.extraSources == [ ] then
      cfg.source
    else
      pkgs.writeText "inspr-agent-kernel.md" payloadText;

  replaceFiles = lib.mapAttrs' (_name: target: {
    name = target;
    value.source = payloadFile;
  }) cfg.harnesses;

  markerScript = pkgs.writeText "inspr-agent-kernel-markers.py" ''
    import pathlib, sys
    dest = pathlib.Path(sys.argv[1])
    payload = pathlib.Path(sys.argv[2]).read_text()
    begin = "<!-- inspr.agent-kernel BEGIN -->"
    end = "<!-- inspr.agent-kernel END -->"
    block = begin + "\n" + payload.rstrip() + "\n" + end + "\n"
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        dest.write_text(block)
        raise SystemExit(0)
    text = dest.read_text()
    if begin in text and end in text:
        pre = text.split(begin, 1)[0]
        post = text.split(end, 1)[1]
        if post.startswith("\n"):
            post = post[1:]
        dest.write_text(pre + block + post)
    else:
        dest.write_text(block + "\n" + text)
  '';
in
{
  options.inspr.agent-kernel = {
    enable = lib.mkEnableOption "declarative INSPR kernel injection into CLI harness global context files";

    source = lib.mkOption {
      type = lib.types.path;
      default = ../../docs/AGENTS-KERNEL.md;
      defaultText = lib.literalExpression "inspr-modules' docs/AGENTS-KERNEL.md";
      description = ''
        Public kernel file. The atelier default is identity-free.
      '';
    };

    extraSources = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Extra markdown files concatenated after `source` (studio private
        kernel). Empty by default so the atelier ships no identity.
      '';
    };

    harnesses = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        pi = ".pi/agent/AGENTS.md";
      };
      description = ''
        Replace-mode targets relative to home. The whole file is the
        payload. No `force`: an existing user file blocks activation.
        Default is Pi only.
      '';
    };

    markerHarnesses = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Marker-mode targets relative to home. A bounded comment block is
        upserted; the rest of the file is preserved. Use for existing
        ~/.codex/AGENTS.md and ~/.claude/CLAUDE.md.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (lib.attrNames cfg.harnesses) != [ ] || (lib.attrNames cfg.markerHarnesses) != [ ];
        message = ''
          inspr.agent-kernel.enable = true requires at least one replace
          harness or marker harness.
        '';
      }
    ]
    ++ lib.mapAttrsToList (name: path: {
      assertion = path != "" && !(lib.hasPrefix "/" path);
      message = ''
        inspr.agent-kernel.harnesses.${name} = "${path}" must be a non-empty
        path relative to the home directory (no leading "/").
      '';
    }) cfg.harnesses
    ++ lib.mapAttrsToList (name: path: {
      assertion = path != "" && !(lib.hasPrefix "/" path);
      message = ''
        inspr.agent-kernel.markerHarnesses.${name} = "${path}" must be a
        non-empty path relative to the home directory (no leading "/").
      '';
    }) cfg.markerHarnesses;

    home.file = replaceFiles;

    home.activation.insprAgentKernelMarkers = lib.mkIf (cfg.markerHarnesses != { }) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatStringsSep "\n" (
          [
            "payload=${lib.escapeShellArg "${payloadFile}"}"
          ]
          ++ lib.mapAttrsToList (_n: rel: ''
            ${pkgs.python3}/bin/python3 ${markerScript} "$HOME/${rel}" "$payload"
          '') cfg.markerHarnesses
        )
      )
    );
  };
}
