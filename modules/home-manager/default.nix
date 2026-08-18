# Aggregate: import all INSPR Home Manager modules in one go. The included
# paimos-config module manages routing only; it never manages credentials.
#
# Consumers who want à-la-carte should import individual modules instead:
#   # `inspr-cli` is deliberately NOT in this aggregate. It renders a
  # `fleet.conf`, so enabling it as a side effect of importing `default`
  # would write a config file the consumer never asked for. Import
  # `homeManagerModules.inspr-cli` by name if you want it.
  imports = [
#     inputs.inspr-modules.homeManagerModules.git-identity
#     # only what you need
#   ];
{ ... }:
{
  imports = [
    ./agent-secrets.nix
    ./agent-skills.nix
    ./devenv-direnv-fix.nix
    ./git-atelier-credentials.nix
    ./git-identity.nix
    ./paimos-config.nix
    ./ssh-authorized.nix
  ];
}
