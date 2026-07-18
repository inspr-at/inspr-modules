# Aggregate: import all INSPR Home Manager modules in one go. The included
# paimos-config module manages routing only; it never manages credentials.
#
# Consumers who want à-la-carte should import individual modules instead:
#   imports = [
#     inputs.inspr-modules.homeManagerModules.git-identity
#     # only what you need
#   ];
{ ... }:
{
  imports = [
    ./agent-secrets.nix
    ./devenv-direnv-fix.nix
    ./git-atelier-credentials.nix
    ./git-identity.nix
    ./paimos-config.nix
    ./ssh-authorized.nix
  ];
}
