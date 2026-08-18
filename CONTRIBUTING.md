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
body; the diff already shows what. No sign-off required.

**Licensing:** by contributing you agree your work ships under **AGPL-3.0-only**,
the licence of this repository.

## Review

One maintainer, no second reviewer, no SLA. If a PR goes quiet for two weeks,
comment on it — that is a nudge, not a nag.

There is no `CODEOWNERS`-driven auto-assignment beyond the maintainer, and no
merge queue. What you see in the PR history is what happens.
