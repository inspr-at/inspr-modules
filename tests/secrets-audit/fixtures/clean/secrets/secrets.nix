# Test fixture: clean — declarations match files on disk; no drift.
let
  user = [ "ssh-ed25519 AAAA-fake-key user" ];
in
{
  "foo.age".publicKeys = user;
  "bar.age".publicKeys = user;
  "agents/shared/baz.age".publicKeys = user;
}
