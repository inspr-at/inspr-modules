# Versioning Doctrine

This file is the normative INSPR policy for version-bearing artifacts. It
applies to public, work, and private repositories without requiring private
repository names or operational details to appear in public doctrine.

The words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are used in their
RFC 2119 sense.

## Default and transition

The INSPR default version scheme is **INSPR Calendar Version v2**, identified
in machine-readable metadata as `inspr-calendar-v2` and written as
`YYMMDDhhmmss.0.0`. Its short display label is **`INSPR-VER2`** (see
"Scheme display labels"); the label never replaces the identifier.

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

## Adoption at project start and before deployment

**INSPR Calendar Versioning** is the default for new and existing projects.
The machine scheme remains `inspr-calendar-v2`; the product name is not a new
scheme. This is an automatic agent workflow requirement, not a claim that
publishing this document migrated every consumer.

At project bootstrap, at worker start for release-bearing work, and before
every normal release/deployment, the harness agent MUST read this policy and
record one of these outcomes in the owning project's designated PPM or PMA
tracker (never both), reusing existing adoption work rather than duplicating it:

- **New project:** include `inspr-calendar-v2` in the initial version source,
  release pipeline, explicit scheme metadata and applicable UI surfaces. Use
  the shared presentation bundle below. Record the initial release anchor;
  do not invent a legacy release for a project without one.
- **Existing adoption ticket (explicit):** pick up that ticket as part of the
  next normal deployment. Owner approval already recorded for that scope
  remains valid. Complete the relevant migration and consumer gates before
  claiming adoption; ticket existence alone is not approval to bypass gates.
- **No adoption ticket (implicit):** proactively propose INSPR Calendar
  Versioning as the standard next-deployment change and create/reuse an owning
  adoption ticket with the concrete inventory and scope. The agent MUST NOT
  silently omit the proposal merely because the user requested another change.
  Implement when authorized; otherwise record the pending proposal. An implicit
  recommendation does not authorize rewriting a release or foreign source.
- **Already adopted:** during release preparation resolve the current approved
  shared display configuration and renderer to one exact source commit and
  digest closure, review the pin change and include it in the next release.
  An unchanged upstream pin requires no artificial update. Build and runtime
  never follow a mutable branch. Explicitly selected named templates remain
  selected; a global-default consumer follows saved global defaults.
- **Blocked or excepted:** identify the missing gate or supported ecosystem
  exception, owning ticket, retained scheme/pin and next action. An existing
  explicit adoption commitment may be deferred only by a recorded owner
  decision. An unrelated emergency rollback uses its immutable prior artifact;
  it does not silently migrate or erase the outstanding adoption work.

Report the outcome, adoption ticket, declared scheme, presentation source pin
and verified active surfaces in release evidence. A pinned but inactive bundle
is not adoption. Re-check an outstanding proposal on the next deployment.
Existing published artifacts stay unchanged under the transition rules above.
These rules apply within each project's own trust context and review path.

## Shared presentation from INSPR Calendar Versioning

The editor at `https://inspr.at/versioning/` saves approved presentation data
in `inspr-at/inspr`, `packages/versioning/config/display.json`, with schema
`inspr.calendar-version-display.v2`. Shared named templates live alongside it
in `packages/versioning/config/templates.json`. This saved configuration and
its shared renderer are the default presentation source for new adoptions;
the legacy display-v1 data later in this document is compatibility material.
A presentation schema upgrade is not a change of version scheme.

During release preparation, resolve the approved source once, then vendor an
immutable offline bundle using the source repository's
`scripts/versioning-bundle.mjs <full-source-commit> <expected-config-sha256> <new-directory>`.
The source checkout and requested Git objects must already be available. Pin
the full source commit, expected config digest and independently reviewed
manifest digest. Verify the complete file set, sizes and hashes on every
normal build, including builds outside CI; reject missing, extra, altered or
untracked payloads. Do not calculate expected pins from candidate bytes in the
same validation step. Keep renderer, presentation, interaction, animation
library, license and scheme label table together as listed by the manifest.
Do not substitute the legacy doctrine-file checker for this different
source/closure contract.

Use one thin product adapter around the shared renderer and interaction helper
at all applicable version surfaces. Do not reimplement separator geometry or
copy display settings into handwritten CSS. Web products default to **Pretty**
with **SemVer** available as the reduced display. Auto colors resolve from the
product's actual branding. Native/CLI-only surfaces retain canonical text and
implement equivalent presentation only where supported; record applicability.

All eight segment opacities, including the year, may range from 0 to 100 percent
according to the saved configuration. Pretty may use independent Unicode
separators, colors, size, spacing, raised/lowered placement and optical offsets.
Hover or keyboard focus reveals the usable version and reverses on exit, using
the shared roughly one-second ease-in/ease-out animation and reduced-motion
support. Revealed segment opacity is `0.7 + 0.3 * configuredOpacity`, retaining
the rhythm within 70–100 percent. Click and keyboard activation copy the exact
canonical version, without a decorative `v` or Pretty separators; `.0.0` stays.
Preserve surrounding navigation/button behavior and accessible feedback.

Machine versions, logs, tags, manifests, APIs and clipboard values remain
canonical. Never parse Pretty text or derive a calendar version from a commit
hash. Legacy versions stay explicitly discriminated and render plain until
migration completes. No runtime configuration fetch to the editor is allowed:
existing deployed artifacts keep their bundled bytes until their next release.
Saving in the editor makes data available for the next reviewed consumer build;
it does not prove that any product has consumed it. A named template is an
explicit product choice, with separate provenance: the current bundle CLI
packages only global `display.json` (beside the scheme label table), not
`templates.json` or a selected template.
For a named-template consumer, pin the catalog at the same source commit,
the template ID and the exact selected config bytes with their own independently
reviewed SHA256 digest. Store and verify that selected configuration separately
from the unchanged renderer/global bundle; pass it explicitly to the adapter.
Its normal build checks MUST verify both pins and reject a missing template or
mismatched config. The global bundle digest alone does not verify a template.
Refreshing such a consumer must retain its template selection, never silently
replace it with global defaults.

### Scheme display labels

A surface that names the version scheme, such as a release dialog's "Scheme"
field, MUST show the doctrine label and MUST NOT invent one:

| Machine scheme | Display label |
|---|---|
| `inspr-calendar-v2` | `INSPR-VER2` |
| `inspr-calendar-v1` | `INSPR-VER1` |
| `legacy` | `Legacy` |

The machine-readable source is `packages/versioning/config/schemes.json`
(`inspr.version-scheme-labels.v1`) in `inspr-at/inspr`, shipped as
`schemes.json` in the presentation bundle and read at build time like
`display.json`. A label is presentation only. Metadata, manifests, tags, APIs,
logs and the clipboard keep the machine scheme identifier. An unknown scheme
is an error, never a fallback label.

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

#### Legacy display-v1 compatibility contract

The remainder of this section applies only to consumers still pinned to the
legacy `inspr-modules` display-v1 bundle. Its fixed defaults, year floor and
markup constraints do not apply to the shared presentation-v2 bundle above.
Retain these bytes and checks for compatibility until each consumer upgrades.

A user interface MAY render a v2 coordinate with per-segment weight so that
the twelve digits read as date, time, and suffix instead of one number.
Display weighting is presentation only and changes nothing about the
coordinate.

For legacy display-v1 consumers, the normative source of the weights is the data file
`lib/calendar-version-display.json` in `inspr-modules`
(schema `inspr.calendar-version-display.v1`). The numbers and the CSS below
are rendered from that file by `scripts/render-calendar-version-display.py`
and MUST NOT be edited by hand; `tests/calendar-version-display.sh` fails when
prose, CSS, and data disagree. Consumers read the file at build time from
their vendored `doctrine/` submodule, from the `inspr-modules` flake
(`lib.calendarVersionDisplay`, package `calendar-version-display-css`), or
from a tracked in-repository copy. They MUST NOT fetch it at runtime.

An in-repository copy is allowed only when its consumer-owned CI check pins
the copy to one immutable, full doctrine commit object ID and verifies both
its exact byte count and its lowercase SHA256 digest. Those three literals
(revision, size, and digest) are one reviewed pin: changing any of them is a
consumer upgrade. The check MUST reject an untracked copy or a byte mismatch.
When the `doctrine/` checkout is initialized, it MUST additionally require
that checkout's `HEAD` to equal the pinned revision and compare the copy
byte-for-byte with `doctrine/lib/calendar-version-display.json`. An absent
checkout MAY skip only that additional comparison; it does not relax the
committed size and digest checks. `scripts/check-calendar-version-display-pin.sh`
is the reusable reference check:

```sh
scripts/check-calendar-version-display-pin.sh \
  path/to/calendar-version-display.json \
  "$PINNED_DISPLAY_SIZE" \
  "$PINNED_DISPLAY_SHA256" \
  "$PINNED_DOCTRINE_REVISION" \
  doctrine
```

The three `PINNED_*` values above MUST be checked-in literals in the
consumer's test, not values calculated from the candidate copy at test time.
Every consumer path, including direct submodule and flake reads, MUST carry a
drift test that compares the values it ships against its pinned source.

The file carries an explicit `design_revision`. The legacy authoritative
design is **display design revision 3**. A design revision is a presentation
change only: it is not a version scheme, the scheme stays
`inspr-calendar-v2`, the data schema stays `inspr.calendar-version-display.v1`,
and no coordinate, tag, manifest, or published artifact changes because of it.
Revision 3 supersedes the visual defaults of revisions 1 and 2 as the
authoritative design; those earlier numbers have no remaining normative force.

Because consumers pin bytes rather than track this file, a revision landing
upstream does NOT mean the fleet renders it. Every consumer stays on the
revision it has pinned until its own pin is upgraded deliberately, and each
such upgrade is its own reviewed change in the consumer's repository. An
upstream edit MUST NOT be reported as a fleet-wide visual rollout.

- The segments are the optional `v` prefix, `YY`, `MM`, `DD`, `hh`, `mm`,
  `ss`, and the constant `.0.0`. Weight is opacity (CSS `opacity`, or the
  equivalent alpha in a non-web toolkit) applied to the segment's inherited
  text colour. It is never a different glyph, size, spacing, or separator.
- Default weights, in percent: `v` 20, `YY` 100, `MM` 80, `DD` 100, `hh` 60,
  `mm` 40, `ss` 20, `.0.0` 20. A project MAY raise any weight; it MUST NOT
  lower `YY` below 100.
- `YY`, `MM`, and `DD` take the shared default Schmuckfarbe `#d69b31` as an
  80 percent colour mix into the current text colour,
  `color-mix(in oklab, currentColor, <highlight> 80%)`. This tint is the
  default, not an opt-in: the date is tinted unless a project deliberately
  overrides `--cv2-tint`. A project whose design system defines its own dark
  highlight colour MAY substitute it. The time segments and the suffix keep
  the plain text colour. A colour that carries state meaning in the project
  (live, stale, down, error) MUST NOT be used as the tint.
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

Reference implementation for the web, rendered from the data file:

```css
/* inspr-calendar-v2 display, design revision 3 — generated from lib/calendar-version-display.json, do not edit by hand */
:root{--o-v:.2;--o-yy:1;--o-mm:.8;--o-dd:1;--o-hh:.6;--o-mi:.4;--o-ss:.2;--o-tail:.2;
      --cv2-tint:#d69b31;--cv2-mix:80%}   /* --cv2-tint is the shared default Schmuckfarbe; a project MAY override it */
.cv2{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-variant-numeric:tabular-nums;white-space:nowrap}
.cv2>b{font-weight:inherit}
.cv2 .v{opacity:var(--o-v)} .cv2 .yy{opacity:var(--o-yy)} .cv2 .mm{opacity:var(--o-mm)}
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
