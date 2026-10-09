# Test fixture: with-comments — verifies that the comment-stripper
# correctly ignores commented-out declarations (regression test for the
# false-positive bug we caught during the audit on the m365 declarations).
let
  user = [ "ssh-ed25519 AAAA-fake-key user" ];
in
{
  "active.age".publicKeys = user;
  # "commented-out.age".publicKeys = user;  # this should NOT be flagged as missing
  # TODO: enable once Azure AD app exists:
  # "future-feature.age".publicKeys = user;
}
