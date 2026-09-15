# consent-gate

Identity-free consent primitive for browser-facing surfaces. One manifest per
surface declares categories, services and texts; the gate decides what may
load and what to render. It implements the doctrine pattern
"web surfaces — cookies & consent" (`docs/AGENTS-DOMAIN-DEV.md`):

- **Tier 0** — the manifest has no optional service: nothing is rendered
  except an optional `[data-consent-open]` control that opens the sheet.
- **Tier 1** — only embeds need consent: a contextual placeholder replaces
  each `[data-consent-embed]` element until "load once" (that element, this
  page view) or "always allow" (the named service, persisted). No page-level
  bar.
- **Tier 2** — a service has a tracking destination: a non-modal bar with
  equivalent **reject** and **accept** buttons, a **settings** link and a
  category sheet. Escape or cancelling the sheet during the first prompt
  counts as refusal. Nothing optional loads before an affirmative, persisted,
  purpose-specific choice.

Behaviour that is the same on every surface:

- The decision is a host-only cookie
  `v1;b=<binding>;r=<revision>;v=<textVersion>;g=<cat@at.rev,…>;s=<svc@at.rev,…>;t=<unix>`
  (`SameSite=Lax`, `Secure` on HTTPS, no identifier). `b` is a fingerprint
  of controller, scope and cookie name — a property of the surface, not of
  the visitor — so a record from another controller or host is no decision;
  the gate also refuses to run on a host other than `scope`. Every granted
  category and remembered service carries its own grant time and the
  category revision it was given under: an unrelated later grant does not
  extend an older one, and bumping one category's `revision` invalidates
  only that category. A grant lives `permissionDays` (default 180); a
  refusal is kept `refusalMonths` UTC calendar months (minimum six, default
  six). The manifest's `revision` re-asks everything; `textVersion` records
  the copy the person saw and never resets a decision. Parsing is strict: a
  corrupt or future-dated value is no decision.
- An affirmative Global Privacy Control or Do-Not-Track signal is a refusal:
  no bar, stored, also over an older grant; signal disappearance does not
  revive it. Crawlers see no bar and get nothing.
- Every destination load re-validates cookie, expiry, revision, signal and
  crawler status. A grant that cannot be read back is no grant. A refusal
  that cannot be stored as a cookie falls back to a session-scoped revocation
  that still outranks a surviving grant on the next page.
- Withdrawal (or dropping a category in the sheet) clears exactly the
  storage each affected service declares (`cookie` at its declared path and
  domain, host-only by default; `local`; `session`), plus the gate's own
  conversion marker, runs registered teardown callbacks, tears an active
  embed down (`src` removed, document replaced), sends Consent Mode `denied`
  to a loaded destination and reloads the page, because a loaded tag has no
  reliable teardown. If the refusal can be persisted nowhere, the reload
  carries a `#consent-revoked` marker that the next document evaluates
  before it reads any surviving grant, and it keeps retrying to persist.
- Embeds: **load once** authorises exactly that element for this page view
  and dies with an explicit refusal or the withdrawal of its category;
  **always allow** remembers the named service (its declared purposes) for
  the permission lifetime without granting its whole category. Granting the
  category opens every service in it; dropping it drops them all. The
  settings sheet lists every embed service under its category so one
  provider can be revoked without touching its siblings. A served `srcdoc`
  counts as live content like a served `src`.
- Google destinations run Consent Mode v2 in **basic** mode: `default`
  denied for every key, `update` grants only the keys the service declares,
  then `gtag.js` is injected with `cookie_domain` pinned to the host. A
  conversion fires only on pages that name the service in
  `data-consent-fire`, once per session, and only to that service's own
  tag (`sendTo` must be `<tagId>/<label>`).
- URLs are validated: the privacy link must be an `https:` URL or a
  same-origin path, an embed only activates with an `https:` `data-src` on
  its declared host. Anything else stays inert.

## Files

| File | Purpose |
|---|---|
| `consent-gate.js` | Core (`insprConsentCore`, no DOM: validation, decisions, storage format, guard) + renderer and destination adapter (`insprConsent`). |
| `consent-gate.css` | Reference styles; every token is a `--ic-*` custom property with a neutral fallback. |
| `manifest.schema.json` | JSON Schema for the manifest. |
| `example/manifest.json`, `example/example.html` | A valid manifest and a page that uses it. |
| `../../tests/consent-gate.mjs` | Node test suite (part of `nix flake check`). |
| `../../scripts/check-consent-gate-vendored.sh` | Drift check for a consumer's vendored copy. |

## Manifest

```jsonc
{
  "version": 1,
  "revision": 1,                 // bump only on a material purpose change
  "textVersion": 1,              // bump on copy changes; never resets a decision
  "controller": "…",             // who is responsible for this surface
  "scope": "www.example.invalid", // the surface's host
  "cookieName": "consent",       // host-only decision cookie
  "permissionDays": 180,
  "refusalMonths": 6,            // UTC calendar months, at least six
  "language": "de",              // else <html lang>, else the first text key
  "privacyUrl": "/privacy",      // https URL or same-origin path
  "categories": [ { "id": "necessary", "required": true }, { "id": "marketing", "revision": 1 }, { "id": "embeds" } ],
  "services": [
    { "id": "ads", "category": "marketing", "provider": "…", "purposes": ["conversion measurement"],
      "storage": [ { "kind": "cookie", "name": "_gcl_*", "days": 90 }, { "kind": "local", "name": "_gcl_ls" } ],
      "destination": { "type": "gtag", "tagId": "AW-…", "consent": ["ad_storage", "ad_user_data"],
                       "linkerAcceptIncoming": true, "conversion": { "sendTo": "AW-…/…" } } },
    { "id": "video", "category": "embeds", "provider": "…", "purposes": ["video playback"],
      "embed": { "host": "video.example.invalid" } }
  ],
  "text": { "de": { "bar": {…}, "sheet": {…}, "embed": {…}, "control": "…", "categories": {…}, "services": {…} } }
}
```

Exactly one category is `required`; optional services must sit in an
optional category; each service declares exactly one of `destination` or
`embed` and lists its purposes; declared cookies may name a `path` and a
`domain` (the scope host or one of its parents; host-only by default) and
are cleared only there. `consent` lists the Consent Mode keys the service
may ever set: an undeclared key (for example `ad_personalization`) stays
denied. Validation failures close the gate: nothing optional loads and
nothing is rendered. `manifest.schema.json` mirrors these rules.

## Using it on a surface

1. Copy `consent-gate.js` and `consent-gate.css` into the surface's own
   assets (self-hosted; never a CDN). Record the inspr-modules revision you
   copied from and pin both files in CI:

   ```sh
   scripts/check-consent-gate-vendored.sh path/to/vendored/consent-gate.js <sha256 at the pinned revision> doctrine/packages/consent-gate/consent-gate.js
   scripts/check-consent-gate-vendored.sh path/to/vendored/consent-gate.css <sha256 at the pinned revision> doctrine/packages/consent-gate/consent-gate.css
   ```

   A Go surface embeds the file with the rest of its assets; an Astro or
   static surface puts it under `public/`. Both compare bytes in CI.
2. Put the manifest into the page as
   `<script type="application/json" id="consent-manifest">…</script>`
   (or set `window.insprConsentManifest` before the gate script).
3. Load the gate with `defer`:
   `<script src="/assets/consent-gate.js" defer data-consent-manifest="#consent-manifest" data-consent-fire="ads"></script>`.
   `data-consent-fire` names the services whose conversion fires on this
   page; leave it empty elsewhere.
4. Mark embeds with `<iframe data-consent-embed="video" data-src="…">`.
   Served markup must contain no active provider `src` or `srcdoc`:
   deferred JavaScript cannot prevent the request such an attribute starts
   the moment the element is connected. The gate treats a live `src` as an
   integration error (console warning, best-effort removal), and the guard
   below fails the served HTML.
5. Put a `<button type="button" data-consent-open></button>` in every footer;
   the gate fills the label from `text.<lang>.control`.
6. Map the tokens: `--ic-surface`, `--ic-surface-soft`, `--ic-ink`,
   `--ic-muted`, `--ic-line`, `--ic-accent`, `--ic-focus`, `--ic-radius`,
   `--ic-radius-pill`, `--ic-font`, `--ic-font-heading`, `--ic-shadow`,
   `--ic-shadow-dialog`.
7. Keep the surface's CSP: `script-src 'self'` plus the destination hosts
   only where a destination exists; the gate needs no inline script.
8. Serve the same texts in every language the surface supports; the gate
   picks `manifest.language`, else `<html lang>`.

Programmatic access: `insprConsent.open()`, `insprConsent.withdraw()`,
`insprConsent.granted("marketing")`, `insprConsent.core` (the bound core;
`core.registerTeardown(serviceId, fn)` runs `fn` when that service loses
authorisation, `core.onChange(fn)` reports every decision change).

## Pre-consent guard

`insprConsentCore.guardServedHtml({ manifest, html, requests })` is the
reusable served-HTML and request guard: it reports every active resource
(`script`, `iframe`, `img`, `link`, media, every `srcset` candidate,
protocol-relative and entity-encoded URLs included) whose URL points at a
declared destination or embed host, every gated embed served with
`srcdoc`, and every captured pre-consent request to such a host. Comments,
the manifest JSON, `data-src` and plain anchors are inert. It is a
regex-based scanner over served HTML, not a full HTML parser: use it as a
smoke test next to the browser's request log, not instead of it. Run it in the surface's tests over the served HTML of every public
route, and feed it the browser's request log from a fresh visit.

## Testing on the surface

The core is unit-tested here. The surface owns the browser proof, run on a
CI runner with a real browser: fresh visit (no request to any destination
host), reject, accept (exactly one destination request, Consent Mode order),
settings after a refusal, withdrawal (storage cleared, reload, nothing
afterwards), GPC/DNT over an older grant, rejected and throwing cookie jars,
crawler user agent, conversion scope and dedupe, privacy page. Stub the
destination hosts inside the browser so the suite never reaches them.

## Licence

AGPL-3.0-only, like the rest of this repository. No third-party code is
vendored in this package.
