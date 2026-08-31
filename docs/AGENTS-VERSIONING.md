# Versioning Doctrine

This file is the normative INSPR policy for version-bearing artifacts. It
applies to public, work, and private repositories without requiring private
repository names or operational details to appear in public doctrine.

The words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are used in their
RFC 2119 sense.

## Default and transition

The INSPR default version scheme is **INSPR Calendar Version v1**, identified
in machine-readable metadata as `inspr-calendar-v1` and written as
`YY.MM.DD[.hh.mm.ss]`.

This is a gradual default, not an estate-wide cutover:

- A repository remains on its current, now-legacy scheme until its owner
  approves a dedicated migration ticket and all migration gates below pass.
- Work already in flight MUST finish under the scheme in force when that work
  began unless its ticket explicitly authorizes migration.
- Existing tags, releases, images, packages, artifacts, changelogs, deployed
  versions, and signed attestations MUST NOT be renamed, rewritten, retagged,
  or republished to resemble calendar versions.
- Every product, service, package, image, configuration, schema, protocol,
  dataset, and other release-bearing artifact in a public, work, or private
  repository is in scope. A documented ecosystem exception MAY preserve a
  required external version syntax; it does not exempt the release from the
  migration inventory or the canonical release mapping.

Until a repository completes its own migration, its established release
policy remains authoritative. There is no implicit migration merely because a
dependency, sibling repository, or deployment target has migrated.

## Calendar coordinate

### Syntax

A canonical calendar version is exactly one of:

```text
YY.MM.DD
YY.MM.DD.hh.mm.ss
```

Its lexical grammar is:

```regex
^(?:[0-9]{2})\.(?:0[1-9]|1[0-2])\.(?:0[1-9]|[12][0-9]|3[01])(?:\.(?:[01][0-9]|2[0-3])\.(?:[0-5][0-9])\.(?:[0-5][0-9]))?$
```

The regex is necessary but not sufficient: implementations MUST also reject
dates that do not exist in the proleptic Gregorian calendar, such as
`26.02.29` and `26.04.31`.

- `YY` means the UTC year in the closed range 2000–2099, encoded as `00`–`99`.
  A successor doctrine MUST define the post-2099 representation before 2099;
  implementations MUST NOT guess a century.
- `MM` is `01`–`12`; `DD` is zero-padded and valid for that month and year.
- `hh` is `00`–`23`; `mm` and `ss` are `00`–`59`.
- Every field is fixed-width ASCII decimal. Whitespace, signs, omitted zeroes,
  fractional seconds, timezone suffixes, prerelease labels, and build metadata
  are not part of the canonical version.
- A tag MAY prepend one literal `v` (for example `v26.08.31`), but the stored
  version value and API field MUST omit it.

### Time basis and reservation

All fields are based on **UTC**. A release coordinate MUST be reserved once,
recorded in the repository's authoritative version source, and then reused by
every build, package, image, manifest, signature, SBOM, and release note for
that release. Build nodes MUST NOT independently derive the version from their
local clocks.

The short form `YY.MM.DD` is allowed when the release channel publishes at most
one changed artifact set for that UTC date. For ordering, it normalizes to
`YY.MM.DD.00.00.00`.

The time suffix is REQUIRED when:

- another non-byte-identical artifact set has already reserved the short form
  or another coordinate on the same date and channel;
- the channel normally publishes more than once per UTC day; or
- an unambiguous coordinate is needed for a rebuild, hotfix, or resumed release.

A suffixed coordinate records the UTC reservation second. It MUST be strictly
later than the channel's previous calendar coordinate. If two release
candidates would reserve the same second, the later reservation waits for the
next second; inventing a hidden tie-breaker or overwriting the first coordinate
is forbidden. A repository MAY require the long form for every release.

## Ordering, immutability, and rollback

Within `inspr-calendar-v1`, compare the six normalized integer fields
`(year, month, day, hour, minute, second)` in order. Fixed-width lexical order
is therefore chronological for supported values. Comparison MUST occur only
after full calendar validation; invalid input has no ordering.

A reserved or published version is immutable:

- One version identifies one immutable, enumerated artifact set through a
  release-set manifest. The manifest records the source-tree and dependency-lock
  provenance and, for every output, a unique artifact coordinate (including
  applicable package/format, platform, architecture, and variant dimensions)
  plus its digest. Different coordinates in one multi-platform or multi-variant
  release MAY and normally do have different bytes and digests.
- Immutability applies per artifact coordinate: a published
  `(release channel, version, artifact coordinate)` MUST keep the same bytes and
  digest. The release-set manifest itself is immutable; outputs MUST NOT be
  added, removed, replaced, or relabelled under an existing version. A changed
  artifact or set receives a new, later coordinate.
- A reproducible rebuild of one artifact coordinate MAY retain the version only
  when the repository's reproducibility policy proves identity with that
  coordinate's published bytes and digest. Otherwise it receives a new, later
  version and a new release-set manifest.
- Mutable aliases such as `latest` MAY point at an immutable artifact, but are
  never versions and never constitute release evidence.
- Rollback deploys a previously published artifact by exact version, artifact
  coordinate, and digest from the immutable release-set manifest, records a new
  deployment event, and leaves release ordering untouched. A rollback fix is a
  new release with a later coordinate; versions are never decremented, reused,
  or force-moved.

## Mixed-era contract

Calendar versions and legacy versions are different tagged types. Tooling MUST
NOT infer the scheme from punctuation or segment count: strings such as
`26.10.31` can be syntactically plausible under more than one scheme.

Every migrated release surface MUST provide, directly or through an immutable
release manifest:

```text
version_scheme   = inspr-calendar-v1
version          = <canonical calendar version>
release_channel  = <stable channel identifier>
release_sequence = <monotonically increasing channel ordinal>
```

The migration record additionally pins `last_legacy_version`,
`first_calendar_version`, and the first calendar `release_sequence`. Raw
legacy and calendar strings are compared only within their own scheme.
Cross-era ordering comes from the channel's immutable release sequence and
explicit migration anchor, never from SemVer comparison, lexical guesswork, or
coercion of calendar fields into `MAJOR.MINOR.PATCH`.

During the compatibility window, readers that can encounter both eras MUST:

1. parse a discriminated `legacy` or `inspr-calendar-v1` value;
2. preserve and display the original version string;
3. compare within a scheme using that scheme's rules;
4. compare across the boundary only through the migration anchor and release
   sequence; and
5. fail closed on an absent, unknown, ambiguous, or invalid scheme.

The window ends only after inventory evidence proves that no supported client,
updater, deployment pin, API consumer, automation, or rollback path still
depends on the legacy-only representation. Removing legacy parsing is a
separate, owner-approved compatibility change.

## Consumer and supply-chain gates

Before calendar versions become authoritative for a repository, its migration
ticket MUST account for and test every applicable surface:

- the single authoritative version source and release-coordinate reservation;
- Git tags, forge releases, changelogs, packages, archives, OCI tags and
  digests, Nix derivations, lock files, SBOMs, signatures, provenance, and
  attestations;
- CI release conditions, sorting, range checks, upgrade/downgrade decisions,
  update feeds, dependency and deployment pins, backup labels, and rollback;
- public UI, CLI output, API schemas, telemetry, support diagnostics, and
  operator runbooks; and
- every parser or consumer that assumes SemVer, calls a SemVer library, uses a
  package-manager range, or sorts unvalidated strings.

Executable tests MUST cover valid and invalid calendar dates, short and long
forms, same-day collisions, mixed-era ordering, absent/unknown scheme values,
dependency and pin updates, a release build, and an exact-artifact rollback.
Release evidence MUST identify the version, source commit, immutable artifact
digest, and validation run without exposing secrets.

CI, APIs, release tooling, update checks, telemetry, and documentation MUST
never silently interpret `inspr-calendar-v1` as SemVer or a legacy version as a
calendar version. Generic utilities such as `sort -V` are not acceptable
scheme-aware comparators.

### Ecosystem exceptions

If an external ecosystem requires another syntax (for example an ecosystem
that accepts only SemVer), the owning migration ticket MUST document:

- the external constraint and the smallest compatibility representation;
- an injective mapping from the canonical calendar release to the external
  artifact version;
- where both values and `version_scheme` are published;
- how consumers, signatures, dependency ranges, update channels, and rollback
  resolve that mapping; and
- an executable round-trip test proving one external version cannot map to two
  calendar releases or vice versa.

An exception is local to that surface. It MUST NOT silently make the external
syntax the product's canonical version or weaken immutability and ordering.

## Per-repository migration gate

Migration requires one owner-approved ticket in the repository's designated
tracker. The ticket MUST:

1. attach the value-free inventory below and identify every affected consumer;
2. choose the authoritative version source and short/long-form policy;
3. define the legacy-to-calendar anchor and compatibility window;
4. update producers and consumers together, including ecosystem mappings;
5. add the executable gates above and retain a tested rollback path;
6. publish one immutable candidate and verify its metadata, digest, signatures,
   update path, deployment pin, public representation, and live behavior; and
7. record the evidence before declaring calendar versions authoritative.

A repository MUST remain on its legacy scheme if any required consumer,
mapping, rollback path, or validation is unknown or red. Adoption by one
repository does not authorize another repository's migration.

## Value-free estate inventory

The estate inventory tracks coverage without publishing private topology or
credentials. Use one row per independently versioned surface:

| Field | Required content |
|---|---|
| Repository alias | Stable non-sensitive alias; never a private remote URL |
| Visibility class | `public`, `work`, or `private` |
| Artifact class | Product, service, package, image, config, schema, protocol, dataset, or other |
| Current scheme | Scheme identifier, not an inferred label |
| Version source | Repository-relative path or value-free source class |
| Release surfaces | Tag, forge release, archive, package, image, manifest, API, UI, or telemetry classes |
| Consumers | Value-free parser, updater, dependency, pin, and support-tool classes |
| Deployment boundary | Non-sensitive environment class; no hostname, address, or credential |
| Rollback reference | Procedure or test identifier and immutable-artifact requirement |
| External constraints | Ecosystem and required compatibility syntax, or `none` |
| Migration anchor | Last legacy / first calendar / sequence fields, or `not-set` |
| Owning ticket | Exactly one repository migration ticket |
| Owner role | Role, never a credential or unnecessary personal identifier |
| Status and evidence | `legacy`, `candidate`, or `authoritative`; value-free test/release references |

Inventory entries MUST NOT contain secrets, tokens, credentials, private
prompts, raw payloads, private repository contents, internal addresses, or
unnecessary personal data. Private surfaces may be represented by stable opaque
aliases while retaining the same completeness and migration gates.

## Examples

Valid coordinates include `26.08.31`, `26.08.31.14.05.09`, `24.02.29`, and
`00.01.01.00.00.00`. Invalid coordinates include `2026.08.31`, `26.8.31`,
`26.02.29`, `26.04.31`, `26.08.31.24.00.00`, `26.08.31.12.60.00`, and
`26.08.31.12.00`.

These examples describe the format; they do not authorize a repository to
migrate without its own completed gate.
