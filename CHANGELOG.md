# Changelog

All notable changes to **inspr-modules** are documented here. The repository is
licensed AGPL-3.0-only (see [LICENSE](LICENSE)).

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
with [Semantic Versioning](https://semver.org/spec/v2.0.0.html) through 0.17.0
and [INSPR Calendar Versioning](docs/AGENTS-VERSIONING.md) after it: first as
`inspr-calendar-v2` (`INSPR-CalVer2`), then `inspr-calver-3` (`INSPR-CalVer3`)
with the identical coordinate. Earlier releases retain their original versions
in the private archive.

---

## [Unreleased]

---

## [261009132555.0.0] - 2026-10-09

### Changed

- **Fresh public history (INSPR-299).** The repository was re-created with a clean
  history; releases up to `261008075622.0.0` and their tags are archived privately.
  Consumers re-pin to the first release of this history. Module options, packages
  and existing checks are unchanged by this reset. The reset also removed
  operator-specific provenance and examples from the documentation, module
  comments and test fixtures, and made the leak guard generic: operator
  patterns now come from a private source, trusted CI runs require it, and a
  new check covers the pattern sources.
