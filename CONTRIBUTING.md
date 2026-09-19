# Contributing

## The short version

Outside contributions are welcome, small ones especially. There is **one
maintainer** — [@markus-barta](https://github.com/markus-barta) — who reviews
and merges everything. Expect days, not hours.

**Open an issue before writing anything non-trivial.** Not bureaucracy: this
repository is extracted from a fleet that is actually running, and some designs
that look arbitrary are load-bearing. A short issue saves you writing a PR that
gets declined for a reason nobody wrote down.

## What is likely to be accepted

- Bug fixes, with a test that fails before and passes after
- Making a module work on a setup other than the maintainer's
- Documentation that removes an assumption only an insider could have
- Making an example work as written — see below, this has bitten us
- Reports and fixes for the guard scripts missing something

## What is likely to be declined

- New modules for problems this fleet does not have. The bar is "reusable
  mechanics", not "everything Nix".
- Options that only make sense with the maintainer's specific hosts, tracker or
  naming
- Large refactors without a prior issue
- Anything that removes a safety assertion to make a test pass

## Practical rules

**Every example must evaluate.** An outside reviewer copied the sole NixOS
module's documented example and it threw — it trusted an SSH key alias that was
never declared. There is now a test that compiles that example
(`tests/module-eval/nixos-ssh-authorized.test.nix`). If you change an example,
change its test. An example nobody executes is a claim, not documentation.

**Run the checks before opening a PR:**

```sh
nix flake check          # module-eval tests, licence + repository surface
./scripts/leak-guard.sh  # refuses operator-identifying content
```

Both must pass. CI runs them as required checks, so a red PR cannot merge.

**Both guard scripts are known incomplete** (INSPR-300). If you find a way to
make either report success on a repository that is genuinely broken, that is a
valuable bug report, not a nuisance — see `SECURITY.md`.

**Commits:** conventional-ish subjects (`fix(module): …`). Explain *why* in the
body; the diff already shows what. Sign off every new contribution commit with
`git commit -s`, using your own name and email after reading [DCO](DCO).

**Licensing:** by contributing you agree your work ships under **AGPL-3.0-only**,
the licence of this repository.

## Developer Certificate of Origin

New contributions use the unmodified [Developer Certificate of Origin 1.1](DCO).
A `Signed-off-by: Name <email>` trailer records that you have the right to submit
the contribution under the project licence. It is not a cryptographic signature
or a guarantee of correctness. Use the same identity as the commit author;
a GitHub-associated noreply address is fine. Sign-offs remain in public history.
This applies to maintainers and outside contributors alike, from adoption onward;
existing history is not rewritten. After reading the DCO, create each new commit
with `git commit -s` using your own name and GitHub-associated email.

Fork the repository, create a branch from the current upstream `main`, implement
and test your change, then push to your fork and open a pull request to `main`.
Describe the change, its purpose, tests, and any limitations. Contributors need
no write access to this repository. The maintainer reviews agent findings and
decides whether to merge; passing checks never grants an agent merge authority.

The required `dco` check validates every commit introduced by a PR, including
merge commits on the contributor branch. An empty or incomplete range fails.
It reads real Git trailers, so a sign-off quoted in prose does not count.
Missing sign-offs must be supplied by the contributor, not invented by a reviewer
or agent. Do not rewrite shared history to repair them without explicit agreement.

Bots are not exempt. Dependabot's native `Signed-off-by` service address is
accepted for its exact GitHub author identity; other bots use their own matching
author/sign-off identity. This checks declarations, not account authenticity.
For agent-assisted work, the human contributor must understand and authorize
their DCO declaration; the agent must not invent identities or sign for others.

GitHub web commits require sign-off. For squash merges, retain the original
commit messages and move their existing sign-off declarations into the final
trailer block; an indented or quoted sign-off is not a trailer. Check that the
final author still has a matching declaration. Never invent a contributor's
sign-off. Use a regular merge when combining authors would obscure provenance.
Release and deployment remain maintainer-controlled. Existing review and CI
requirements still apply; DCO introduces no second-maintainer requirement.

## Review

One maintainer, no second reviewer, no SLA. If a PR goes quiet for two weeks,
comment on it — that is a nudge, not a nag.

There is no `CODEOWNERS`-driven auto-assignment beyond the maintainer, and no
merge queue. What you see in the PR history is what happens.
