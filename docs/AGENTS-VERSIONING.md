# Versioning Doctrine

This file is the normative INSPR policy for version-bearing artifacts. It
applies to public, work, and private repositories without requiring private
repository names or operational details to appear in public doctrine.

The words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are used in their
RFC 2119 sense.

## Default and transition

The INSPR default version scheme is **INSPR Calendar Version v2**, identified
in machine-readable metadata as `inspr-calendar-v2` and written as
`YYMMDDhhmmss.0.0`.

It supersedes **INSPR Calendar Version v1** (`inspr-calendar-v1`,
`YY.MM.DD[.hh.mm.ss]`). v1 was not syntactically valid SemVer because its
zero-padded segments are illegal SemVer numeric identifiers, and its variable
segment count let the first two adopting repositories drift apart. v1 is now a
legacy scheme like any other: repositories that adopted it keep it until their
own migration is complete, and every v1 coordinate they published stays exactly
as published.

This is a gradual default, not an estate-wide cutover:

- A repository remains on its current, now-legacy scheme (SemVer, v1, or any
  other) until its owner approves a dedicated migration ticket and all
  migration gates below pass.
- Work already in flight MUST finish under the scheme in force when that work
  began unless its ticket explicitly authorizes migration.
- Existing tags, releases, images, packages, artifacts, changelogs, deployed
  versions, and signed attestations MUST NOT be renamed, rewritten, retagged,
  or republished to resemble calendar versions.
- A repository on v1 MUST NOT patch v1 grammar deviations in place; the
  deviation is resolved by that repository's v2 migration.
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

A canonical calendar version is exactly:

```text
YYMMDDhhmmss.0.0
```

Its lexical grammar is:

```regex
^(?:[1-9][0-9])(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])(?:[01][0-9]|2[0-3])(?:[0-5][0-9])(?:[0-5][0-9])\.0\.0$
```

The regex is necessary but not sufficient: implementations MUST also reject
dates that do not exist in the proleptic Gregorian calendar, such as
`260229120000.0.0` and `260431120000.0.0`.

- The first segment (SemVer MAJOR) is the UTC reservation timestamp,
  twelve fixed-width ASCII decimal digits: `YY` year 2010–2099 encoded as
  `10`–`99`, `MM` month `01`–`12`, `DD` day valid for that month and year,
  `hh` hour `00`–`23`, `mm` minute `00`–`59`, `ss` second `00`–`59`. A
  successor doctrine MUST define the post-2099 representation before 2099;
  implementations MUST NOT guess a century.
- The year range starts at `10` so the segment can never begin with a zero.
  Real reservations are later than the doctrine itself, so no conforming
  coordinate is affected; the bound exists to keep the grammar SemVer-clean.
- The second and third segments (SemVer MINOR and PATCH) are the literal
  constant `0.0`. They never increment. A changed artifact set receives a new,
  later timestamp; there is no patch, hotfix, or rebuild counter.
- There is no short form. A bare `YYMMDD` parses as an integer in YAML, Nix,
  and spreadsheets, and a padded midnight would misrepresent the reservation.
- Whitespace, signs, omitted zeroes, fractional seconds, timezone suffixes,
  prerelease labels, and build metadata are not part of the canonical version
  and MUST NOT be appended.
- A tag MAY prepend one literal `v` (for example `v260909113550.0.0`), but the
  stored version value and API field MUST omit it.

### SemVer syntax without SemVer semantics

A canonical v2 coordinate is a syntactically valid Semantic Versioning 2.0.0
string. This is deliberate: SemVer-enforcing consumers (chart repositories,
package registries, compliance scanners, generic release tooling) accept it,
and their precedence rules yield chronological order because only the first
segment varies.

It is **not** SemVer-semantic:

- A larger MAJOR means "later", nothing more. Compatibility, breaking-change,
  caret, and tilde semantics do not apply. A consumer that classifies every
  release as a major change is behaving as intended; that is the defensive
  reading INSPR chooses.
- Producers MUST NOT append a prerelease (`-…`) or build-metadata (`+…`)
  suffix. OCI tags forbid `+`, and everything after `-` is a prerelease to
  SemVer tooling, which would sort the release before its own timestamp and
  hide it from stable channels. Source commit, build identity, and provenance
  belong in the immutable release-set manifest, attestation, and SBOM.
- The first segment exceeds 32-bit integer range. A consumer that parses SemVer
  segments into 32-bit integers is a non-conforming consumer and MUST be listed
  and fixed in the migration inventory; it MUST NOT be worked around by
  shortening the coordinate.

### Time basis and reservation

All fields are based on **UTC**. A release coordinate MUST be reserved once,
recorded in the repository's authoritative version source, and then reused by
every build, package, image, manifest, signature, SBOM, and release note for
that release. Build nodes MUST NOT independently derive the version from their
local clocks.

The coordinate records the UTC reservation second. It MUST be strictly later
than the channel's previous calendar coordinate. If two release candidates
would reserve the same second, the later reservation waits for the next
second; inventing a hidden tie-breaker or overwriting the first coordinate is
forbidden.

### Display weights

A user interface MAY render a v2 coordinate with per-segment weight so that
the twelve digits read as date, time, and suffix instead of one number.
Display weighting is presentation only and changes nothing about the
coordinate.

- The segments are the optional `v` prefix, `YY`, `MM`, `DD`, `hh`, `mm`,
  `ss`, and the constant `.0.0`. Weight is opacity (CSS `opacity`, or the
  equivalent alpha in a non-web toolkit) applied to the segment's inherited
  text colour. It is never a different glyph, size, spacing, or separator.
- Default weights, in percent: `v` 20, `YY` 100, `MM` 70, `DD` 70, `hh` 90,
  `mm` 60, `ss` 20, `.0.0` 10. A project MAY raise any weight; it MUST NOT
  lower `YY` below 100.
- If the project's design system defines a dark highlight colour
  (Schmuckfarbe), `YY`, `MM`, and `DD` take it as a 50 percent colour mix into
  the current text colour, for example
  `color-mix(in oklab, currentColor, <highlight> 50%)`. The time segments and
  the suffix keep the plain text colour. A colour that carries state meaning
  in the project (live, stale, down, error) MUST NOT be used as the tint.
  Without such a highlight colour the date stays untinted.
- The rendered element's text content and every machine-facing surface
  (clipboard, logs, JSON, CLI output, tags, manifests) carry the plain
  canonical string only. Weighting MUST NOT split, reorder, or annotate the
  string.
- Weighted coordinates use a monospace face with tabular numerals so segments
  align across rows.
- Weighting applies to `inspr-calendar-v2` only. Legacy v1 and SemVer-legacy
  versions render plain, and the scheme MUST come from the release record,
  never from the shape of the string.
- Each project implements exactly one helper that emits the weighted markup
  and uses it everywhere a version is displayed.

Reference implementation for the web:

```css
:root{--o-v:.2;--o-yy:1;--o-mm:.7;--o-dd:.7;--o-hh:.9;--o-mi:.6;--o-ss:.2;--o-tail:.1;
      --cv2-tint:currentColor;--cv2-mix:50%}          /* set --cv2-tint to the Schmuckfarbe */
.cv2{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-variant-numeric:tabular-nums;white-space:nowrap}
.cv2>b{font-weight:inherit}
.cv2 .v{opacity:var(--o-v)}   .cv2 .yy{opacity:var(--o-yy)} .cv2 .mm{opacity:var(--o-mm)}
.cv2 .dd{opacity:var(--o-dd)} .cv2 .hh{opacity:var(--o-hh)} .cv2 .mi{opacity:var(--o-mi)}
.cv2 .ss{opacity:var(--o-ss)} .cv2 .tail{opacity:var(--o-tail)}
.cv2 .yy,.cv2 .mm,.cv2 .dd{color:color-mix(in oklab,currentColor,var(--cv2-tint) var(--cv2-mix))}
```

```html
<span class="cv2"><b class="v">v</b><b class="yy">26</b><b class="mm">09</b><b class="dd">09</b><b class="hh">20</b><b class="mi">25</b><b class="ss">06</b><b class="tail">.0.0</b></span>
```

## Ordering, immutability, and rollback

Within `inspr-calendar-v2`, compare the first segment as one integer. Because
every canonical coordinate has the same width, this is identical to plain
lexical ordering of the canonical strings, so `git tag`, registry listings,
and directory listings order chronologically without a scheme-aware sorter.
Comparison MUST nevertheless occur only after full grammar and calendar
validation; invalid input has no ordering. Lexical order across eras
(SemVer-legacy, v1, v2) is meaningless and MUST NOT be used.

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

Legacy versions, `inspr-calendar-v1` versions, and `inspr-calendar-v2`
versions are different tagged types. Tooling MUST NOT infer the scheme from
punctuation, segment count, or width: a v2 coordinate is also a syntactically
valid SemVer string, and strings such as `26.10.31` are plausible under more
than one scheme. Shape is provably insufficient.

Every migrated release surface MUST provide, directly or through an immutable
release manifest:

```text
version_scheme   = inspr-calendar-v2
version          = <canonical calendar version>
release_channel  = <stable channel identifier>
release_sequence = <monotonically increasing channel ordinal>
```

The migration record additionally pins `last_legacy_version`,
`first_calendar_version`, and the first calendar `release_sequence`. For a
repository migrating from v1, `last_legacy_version` is its last v1 coordinate
and the record MUST name `inspr-calendar-v1` as the legacy scheme. Raw
strings are compared only within their own scheme. Cross-era ordering comes
from the channel's immutable release sequence and explicit migration anchor,
never from SemVer comparison, lexical guesswork, or coercion of calendar
fields into `MAJOR.MINOR.PATCH`.

During the compatibility window, readers that can encounter more than one era
MUST:

1. parse a discriminated `legacy`, `inspr-calendar-v1`, or `inspr-calendar-v2`
   value;
2. preserve and display the original version string;
3. compare within a scheme using that scheme's rules (v1 keeps its six-field
   normalized comparison; v2 compares the first segment as one integer);
4. compare across an era boundary only through the migration anchor and
   release sequence; and
5. fail closed on an absent, unknown, ambiguous, or invalid scheme.

The window ends only after inventory evidence proves that no supported client,
updater, deployment pin, API consumer, automation, or rollback path still
depends on an older representation. Removing legacy or v1 parsing is a
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
- every parser or consumer that assumes SemVer semantics, applies a SemVer
  range, parses segments into 32-bit integers, calls a version library with a
  scheme it was not told about, or sorts unvalidated strings.

Executable tests MUST cover valid and invalid calendar dates, rejection of v1
and SemVer-legacy strings by the v2 parser, rejection of prerelease and
build-metadata suffixes, same-second collisions, mixed-era ordering,
absent/unknown scheme values, dependency and pin updates, a release build, and
an exact-artifact rollback. Release evidence MUST identify the version, source
commit, immutable artifact digest, and validation run without exposing
secrets.

CI, APIs, release tooling, update checks, telemetry, and documentation MUST
never silently interpret `inspr-calendar-v2` as a semantic version, a legacy
version as a calendar version, or v1 as v2.
Generic utilities such as `sort -V` are not acceptable scheme-aware
comparators, even though they happen to order canonical v2 strings correctly;
a comparator MUST validate first.

### Ecosystem exceptions

`inspr-calendar-v2` needs no exception for SemVer-syntax ecosystems, OCI tags,
Git tags, URLs, or file names. If an external ecosystem still requires another
syntax (for example a bounded integer field or a fixed digit count), the owning
migration ticket MUST document:

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
2. choose the authoritative version source;
3. define the legacy-to-calendar anchor and compatibility window;
4. update producers and consumers together, including ecosystem mappings;
5. add the executable gates above and retain a tested rollback path;
6. publish one immutable candidate and verify its metadata, digest, signatures,
   update path, deployment pin, public representation, and live behavior; and
7. record the evidence before declaring calendar versions authoritative.

A repository MUST remain on its current scheme if any required consumer,
mapping, rollback path, or validation is unknown or red. Adoption by one
repository does not authorize another repository's migration. A repository
already on v1 goes through this same gate to reach v2.

## Value-free estate inventory

The estate inventory tracks coverage without publishing private topology or
credentials. Use one row per independently versioned surface:

| Field | Required content |
|---|---|
| Repository alias | Stable non-sensitive alias; never a private remote URL |
| Visibility class | `public`, `work`, or `private` |
| Artifact class | Product, service, package, image, config, schema, protocol, dataset, or other |
| Current scheme | Scheme identifier (`legacy`, `inspr-calendar-v1`, `inspr-calendar-v2`), not an inferred label |
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

Valid coordinates include `260909113550.0.0`, `261231235959.0.0`,
`280229120000.0.0` (2028 is a leap year), and `991231235959.0.0`.

Invalid coordinates include `26.09.09` and `26.09.09.11.35.50` (v1),
`5.21.0` (SemVer-legacy), `20260909113550.0.0` (four-digit year),
`2609091135.0.0` (minute precision), `260909113550` (missing `.0.0`),
`260909113550.0.1`, `260909113550.1.0`, `260909113550.0.0-rc1`,
`260909113550.0.0+g39d0b59`, `260909240000.0.0`, `260909116000.0.0`,
`260229120000.0.0`, `260431120000.0.0`, and `090909113550.0.0`.

These examples describe the format; they do not authorize a repository to
migrate without its own completed gate.

## Prior art

The construction follows [TrunkVer](https://trunkver.org/): a UTC timestamp in
the MAJOR segment with MINOR and PATCH fixed at `0.0`, which is the only way to
be both fixed-width sortable and SemVer-syntactic, because SemVer forbids
leading zeros and only the year segment can never start with one. INSPR
deliberately omits TrunkVer's mandatory `-SOURCEREF-BUILDREF` suffix (it is a
SemVer prerelease and is unknown at reservation time) and uses a two-digit
year so that canonical v2 strings sort after a repository's existing v1 tags.
