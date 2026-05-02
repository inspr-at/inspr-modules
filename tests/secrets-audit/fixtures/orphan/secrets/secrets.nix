# Test fixture: orphan — files exist on disk that aren't declared.
let
  user = [ "ssh-ed25519 AAAA-fake-key user" ];
in
{
  "declared.age".publicKeys = user;
}
