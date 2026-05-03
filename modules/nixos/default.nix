# Aggregate: import all INSPR NixOS modules in one go.
#
# Consumers who want à-la-carte should import individual modules instead:
#   imports = [
#     inputs.inspr-modules.nixosModules.ssh-authorized
#     # only what you need
#   ];
{ ... }:
{
  imports = [
    ./ssh-authorized.nix
  ];
}
