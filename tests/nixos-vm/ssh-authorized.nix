# ─────────────────────────────────────────────────────────────────────────
# tests/nixos-vm/ssh-authorized.nix
#
# End-to-end NixOS VM test for `nixosModules.ssh-authorized`.
#
# Why this exists
# ───────────────
# The module-eval suite proves the module RENDERS the right list of keys.
# It cannot prove that sshd, on a booted system, actually ADMITS the trusted
# key and REJECTS the untrusted one — that is a property of the activated
# system, not of the evaluated attrset. For an SSH admission-control module,
# that gap is the one that matters. An independent reviewer declined to adopt
# the module without exactly this test.
#
# What it proves
# ──────────────
#   1. a trusted alias's key can log in as the configured user
#   2. a key present in the keyring but NOT in the user's trust list is refused
#   3. a revoked alias declared in `keys` (but not trusted) does not admit
#   4. `force = true` yields exactly the rendered list — nothing injected
#   5. multi-user: bob's key does not open alice's account
#
# How keys get in — and why NOT builtins.readFile
# ───────────────────────────────────────────────
# The module takes public keys as strings at eval time. The obvious way to
# supply generated keys — a runCommand + `builtins.readFile` — is
# import-from-derivation: it forces the key build during EVALUATION. Under
# `nix flake check --all-systems`, evaluating the aarch64-linux variant on an
# x86_64 runner tried to build an aarch64 derivation and failed with
# "platform mismatch". `builtins.currentSystem` avoids that but is impure and
# unavailable in a pure `nix flake check`. Committing key fixtures would trip
# push protection and is a bad habit regardless.
#
# So: the module is configured with PLACEHOLDER key strings that keep its real
# input shape (`keys` + `trust` + `status`), and at RUNTIME the client node
# generates fresh keypairs, ships the public halves to the server, and the
# server substitutes them into the file the module rendered. The module's
# OUTPUT — /etc/ssh/authorized_keys.d/<user> — is what sshd reads and what we
# assert on. Nothing is committed, nothing is built at eval.
#
# How it runs
# ───────────
# Requires a Linux builder with KVM (`nixos-test` system feature). Exposed in
# `checks` only on Linux systems, so `nix flake check` on macOS is unaffected.
# GitHub's ubuntu runners have KVM via cachix/install-nix-action.
# ─────────────────────────────────────────────────────────────────────────
{ pkgs, sshAuthorizedModule }:
pkgs.testers.runNixOSTest {
  name = "ssh-authorized";

  nodes = {
    server = { pkgs, ... }: {
      imports = [ sshAuthorizedModule ];
      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
        settings.KbdInteractiveAuthentication = false;
        # The test deliberately makes several FAILING connections in a row
        # before the last SUCCEEDING one. OpenSSH >= 9.8 penalises a source
        # after repeated auth failures and drops the next connection before it
        # reaches key checking — the legitimate bob@bob login was refused with
        # "Connection reset by peer" on the first run. Off for the test only.
        settings.PerSourcePenalties = "no";
      };
      users.users.alice = { isNormalUser = true; };
      users.users.bob = { isNormalUser = true; };

      inspr.ssh.authorized = {
        enable = true;
        keys = {
          "alice@trusted"   = "ssh-ed25519 PLACEHOLDER_ALICE_TRUSTED alice-trusted@test";
          "alice@untrusted" = "ssh-ed25519 PLACEHOLDER_ALICE_UNTRUSTED alice-untrusted@test";  # keyring, NOT trusted
          "bob@laptop"      = "ssh-ed25519 PLACEHOLDER_BOB bob@test";
          "shared-revoked"  = { key = "ssh-ed25519 PLACEHOLDER_REVOKED revoked@test"; status = "revoked"; note = "test"; };
        };
        users.alice = { trust = [ "alice@trusted" ]; force = true; };
        users.bob   = { trust = [ "bob@laptop" ]; };
      };
    };

    client = { pkgs, ... }: {
      environment.systemPackages = [ pkgs.openssh ];
    };
  };

  testScript = ''
    start_all()
    server.wait_for_unit("sshd.service")
    server.wait_for_open_port(22)
    client.wait_for_unit("multi-user.target")

    # Runtime keygen on the client — nothing committed, nothing built at eval.
    names = ["alice-trusted", "alice-untrusted", "bob", "revoked"]
    for n in names:
        client.succeed("ssh-keygen -q -t ed25519 -N \"\" -C " + n + "@test -f /root/" + n)

    # Substitute the placeholders in the module's RENDERED output on the server.
    # We edit only the file sshd reads, so the module's own rendering (which
    # aliases were trusted, force semantics, revoked exclusion) is preserved
    # exactly and remains the thing under test.
    def pubkey(n):
        return client.succeed(f"cut -d' ' -f2 /root/{n}.pub").strip()
    subs = {
        "PLACEHOLDER_ALICE_TRUSTED":   pubkey("alice-trusted"),
        "PLACEHOLDER_ALICE_UNTRUSTED": pubkey("alice-untrusted"),
        "PLACEHOLDER_BOB":             pubkey("bob"),
        "PLACEHOLDER_REVOKED":         pubkey("revoked"),
    }
    for user in ["alice", "bob"]:
        for ph, real in subs.items():
            server.succeed(f"sed -i 's|{ph}|{real}|g' /etc/ssh/authorized_keys.d/{user}")

    def ssh(key, user):
        return ("ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
                "-o BatchMode=yes -o ConnectTimeout=5 -i /root/" + key + " "
                + user + "@server true")

    with subtest("trusted key is admitted"):
        client.succeed(ssh("alice-trusted", "alice"))

    with subtest("keyring key that is not in trust is refused"):
        client.fail(ssh("alice-untrusted", "alice"))

    with subtest("revoked alias does not admit"):
        client.fail(ssh("revoked", "alice"))
        client.fail(ssh("revoked", "bob"))

    with subtest("multi-user isolation: bob's key cannot open alice"):
        client.fail(ssh("bob", "alice"))
        client.succeed(ssh("bob", "bob"))

    with subtest("force=true renders exactly the trusted list on the server"):
        keys = server.succeed("cat /etc/ssh/authorized_keys.d/alice")
        assert keys.count("ssh-ed25519") == 1, "expected exactly one key for alice, got:\n" + keys
        assert "alice-trusted@test" in keys
        assert "alice-untrusted@test" not in keys
        assert "PLACEHOLDER" not in keys, "a placeholder survived substitution"
  '';
}
