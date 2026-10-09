# Test fixture: declared-missing — secrets.nix declares files that don't exist.
let
  user = [ "ssh-ed25519 AAAA-fake-key user" ];
in
{
  "foo.age".publicKeys = user;
  "missing.age".publicKeys = user; # NOT on disk
  "also-missing.age".publicKeys = user; # NOT on disk
}
